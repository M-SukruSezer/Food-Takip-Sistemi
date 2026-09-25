const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const {
  requireAuth, requireRole, resolveStoreScope, storeFilter, allowsStore,
} = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

// Masraf girisi yalnizca magaza kasasini kullanan iki rolde.
const SPENDER_ROLES = ['store_manager', 'shift_supervisor'];
const requireSpender = requireRole(...SPENDER_ROLES);

// Vardiya mudurunun girdigi masraf magaza muduru onayina takilir. Magaza
// mudurunun kendi girisi onay beklemez: onaylayan makam kendisi.
const APPROVER_ROLES = ['store_manager', 'super_admin'];
const NEEDS_APPROVAL_ROLES = ['shift_supervisor'];

// Modulu gorebilenler: masrafi girenler + izleme amacli ust kademeler.
// Barista bu modulu hic gormez.
const VIEWER_ROLES = [
  'super_admin', 'operations_manager', 'regional_manager', ...SPENDER_ROLES,
];

router.use(requireAuth, requireRole(...VIEWER_ROLES));

// Fis fotosu data URL olarak saklanir. Istemci kuculterek gonderir; sunucu
// yine de bicimi ve boyutu dogrular ki devasa bir gorsel veritabanina girmesin.
const RECEIPT_PATTERN = /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/;
const RECEIPT_MAX_CHARS = 900000; // ~650 KB ikili

/// Haftanin baslangici (Pazartesi 00:00 UTC). Limit haftalik oldugu icin
/// harcamalar bu sinira gore toplanir.
function weekStart(date = new Date()) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = (d.getUTCDay() + 6) % 7; // Pazartesi = 0
  d.setUTCDate(d.getUTCDate() - day);
  return d.toISOString();
}

async function limitFor(storeId) {
  const row = await queryOne('SELECT weekly_amount FROM petty_cash_limits WHERE store_id = ?', storeId);
  return row ? Number(row.weekly_amount) : 0;
}

/// Haftalik harcama dokumu.
///
/// Limit kontrolu onayli VE bekleyen masraflari birlikte sayar: para fiilen
/// kasadan cikmistir, onay yalnizca kaydin dogrulanmasidir. Bekleyeni saymamak
/// limitin bekleyen kayit yiginiyla asilmasina izin verirdi. Reddedilen kayit
/// sayilmaz — o harcama kabul edilmemistir.
async function spentThisWeek(storeId) {
  const row = await queryOne(`
    SELECT COALESCE(SUM(CASE WHEN status = 'approved' THEN amount ELSE 0 END),0) AS approved,
           COALESCE(SUM(CASE WHEN status = 'pending'  THEN amount ELSE 0 END),0) AS pending,
           COALESCE(SUM(CASE WHEN status = 'pending'  THEN 1 ELSE 0 END),0) AS pending_count
    FROM petty_cash_expenses
    WHERE store_id = ? AND spent_at >= ? AND status <> 'rejected'
  `, storeId, weekStart());
  const approved = Number(row.approved) || 0;
  const pending = Number(row.pending) || 0;
  return {
    approved,
    pending,
    pendingCount: Number(row.pending_count) || 0,
    total: approved + pending,
  };
}

/// Masraf listesi + haftalik limit durumu.
router.get('/', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;

  const f = storeFilter(scope, 'e.store_id');
  const params = [...f.params];
  let where = f.sql ? ' WHERE' + f.sql.slice(4) : '';
  if (req.query.from) { where += where ? ' AND' : ' WHERE'; where += ' e.spent_at >= ?'; params.push(req.query.from); }
  if (req.query.to) { where += where ? ' AND' : ' WHERE'; where += ' e.spent_at <= ?'; params.push(req.query.to); }

  // Liste fis gorselini tasimaz; tek tek /:id/receipt ile alinir, aksi halde
  // her acilista megabaytlarca veri iner.
  const items = await queryAll(`
    SELECT e.id, e.store_id, e.amount, e.description, e.spent_at, e.created_at,
           e.status, e.decided_at, e.decision_note,
           (e.receipt IS NOT NULL) AS has_receipt,
           u.full_name AS created_by_name, s.name AS store_name,
           d.full_name AS decided_by_name
    FROM petty_cash_expenses e
    LEFT JOIN users u ON u.id = e.created_by
    LEFT JOIN users d ON d.id = e.decided_by
    LEFT JOIN stores s ON s.id = e.store_id
    ${where}
    ORDER BY CASE WHEN e.status = 'pending' THEN 0 ELSE 1 END, e.spent_at DESC
    LIMIT 500
  `, ...params);

  // Limit durumu yalnizca tek magazaya daraltilmissa anlamli.
  let status = null;
  if (scope.storeId) {
    const limit = await limitFor(scope.storeId);
    const spent = await spentThisWeek(scope.storeId);
    status = {
      store_id: scope.storeId,
      weekly_limit: limit,
      spent_this_week: spent.total,
      approved_this_week: spent.approved,
      pending_this_week: spent.pending,
      pending_count: spent.pendingCount,
      remaining: Math.max(0, limit - spent.total),
      week_start: weekStart(),
      can_approve: APPROVER_ROLES.includes(req.user.role),
    };
  }

  res.json({ items: items.map((i) => ({ ...i, has_receipt: !!i.has_receipt })), status });
});

/// Fis gorseli ayri cekilir.
router.get('/:id/receipt', async (req, res) => {
  const row = await queryOne('SELECT store_id, receipt FROM petty_cash_expenses WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Masraf bulunamadı' });
  if (!allowsStore(req, row.store_id)) return res.status(403).json({ error: 'Bu masrafa erişim yetkiniz yok' });
  if (!row.receipt) return res.status(404).json({ error: 'Bu masrafta fiş görseli yok' });
  res.json({ receipt: row.receipt });
});

/// Masraf ekleme. Haftalik limiti asan giris reddedilir.
router.post('/', requireSpender, async (req, res) => {
  const { amount, description, receipt, spent_at } = req.body || {};

  const storeId = req.user.store_id;
  if (!storeId) return res.status(403).json({ error: 'Size mağaza atanmamış' });

  const value = Number(amount);
  if (!Number.isFinite(value) || value <= 0) {
    return res.status(400).json({ error: 'Tutar 0’dan büyük bir sayı olmalıdır' });
  }
  if (!description || !String(description).trim()) {
    return res.status(400).json({ error: 'Açıklama zorunludur' });
  }
  if (receipt !== undefined && receipt !== null) {
    if (typeof receipt !== 'string' || !RECEIPT_PATTERN.test(receipt)) {
      return res.status(400).json({ error: 'Fiş görseli geçersiz' });
    }
    if (receipt.length > RECEIPT_MAX_CHARS) {
      return res.status(400).json({ error: 'Fiş görseli çok büyük' });
    }
  }

  const limit = await limitFor(storeId);
  if (limit <= 0) {
    return res.status(400).json({ error: 'Bu mağaza için haftalık petty cash limiti tanımlanmamış' });
  }
  const spent = await spentThisWeek(storeId);
  const remaining = limit - spent.total;
  if (value > remaining) {
    return res.status(400).json({
      error: `Haftalık limit aşılıyor. Kalan: ${remaining.toFixed(2)} TL`,
    });
  }

  const needsApproval = NEEDS_APPROVAL_ROLES.includes(req.user.role);
  const status = needsApproval ? 'pending' : 'approved';

  const r = await execute(
    `INSERT INTO petty_cash_expenses (store_id, amount, description, receipt, spent_at, created_by, status)
     VALUES (?,?,?,?,COALESCE(?, to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),?,?)
     RETURNING id`,
    storeId, value, String(description).trim(), receipt || null, spent_at || null,
    req.user.id, status
  );
  await logActivity(req.user, 'PETTY_CASH', 'petty_cash', r.lastInsertRowid,
    `${value} TL masraf: ${String(description).trim()}`
    + (needsApproval ? ' (mağaza müdürü onayı bekliyor)' : ''), storeId);

  res.status(201).json({
    id: Number(r.lastInsertRowid),
    status,
    needs_approval: needsApproval,
    remaining: remaining - value,
  });
});

/// Masraf silme.
///
/// Bekleyen kaydi giren kisi geri alabilir. Onaylanmis ya da reddedilmis kayit
/// bir karar tasidigi icin yalnizca Ana Yonetici silebilir; aksi halde
/// vardiya muduru onaylanmis masrafi silip kayittan cikarabilirdi.
router.delete('/:id', async (req, res) => {
  const row = await queryOne('SELECT * FROM petty_cash_expenses WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Masraf bulunamadı' });
  if (!allowsStore(req, row.store_id)) return res.status(403).json({ error: 'Bu masrafa erişim yetkiniz yok' });
  if (req.user.role !== 'super_admin') {
    if (row.created_by !== req.user.id) {
      return res.status(403).json({ error: 'Yalnızca kendi girdiğiniz masrafı silebilirsiniz' });
    }
    if (row.status !== 'pending') {
      return res.status(400).json({
        error: row.status === 'approved'
          ? 'Onaylanmış masraf silinemez'
          : 'Reddedilmiş masraf silinemez',
      });
    }
  }
  await execute('DELETE FROM petty_cash_expenses WHERE id = ?', row.id);
  await logActivity(req.user, 'PETTY_CASH_SIL', 'petty_cash', row.id,
    `${row.amount} TL masraf silindi`, row.store_id);
  res.json({ ok: true });
});

// ---- Onay (vardiya muduru girisleri) ----

/// Onay bekleyen masraflar. Onaylayan makamin kuyrugu.
router.get('/pending', requireRole(...APPROVER_ROLES), async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const f = storeFilter(scope, 'e.store_id');
  const rows = await queryAll(`
    SELECT e.id, e.store_id, e.amount, e.description, e.spent_at, e.created_at,
           e.status, (e.receipt IS NOT NULL) AS has_receipt,
           u.full_name AS created_by_name, u.role AS created_by_role,
           s.name AS store_name
    FROM petty_cash_expenses e
    LEFT JOIN users u ON u.id = e.created_by
    LEFT JOIN stores s ON s.id = e.store_id
    WHERE e.status = 'pending' ${f.sql}
    ORDER BY e.spent_at
  `, ...f.params);
  res.json(rows.map((r) => ({ ...r, has_receipt: !!r.has_receipt })));
});

/// Onayla / reddet. Yalnizca magaza muduru ve Ana Yonetici.
///
/// Karar verilmis kayit tekrar karara acilmaz: ayni masraf iki kez
/// onaylanip limitte cift sayilmasin.
async function decide(req, res, next) {
  const approve = next === 'approved';
  const row = await queryOne('SELECT * FROM petty_cash_expenses WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Masraf bulunamadı' });
  if (!allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu masrafa erişim yetkiniz yok' });
  }
  if (row.status !== 'pending') {
    return res.status(400).json({
      error: row.status === 'approved' ? 'Bu masraf zaten onaylanmış' : 'Bu masraf zaten reddedilmiş',
    });
  }
  // Kendi girdigi masrafi onaylamak anlamsiz: magaza muduru girisi zaten
  // onayli aciliyor. Yine de veri bozulmasina karsi kapatilir.
  if (row.created_by === req.user.id) {
    return res.status(400).json({ error: 'Kendi girdiğiniz masrafı onaylayamazsınız' });
  }

  const note = req.body && req.body.note !== undefined
    ? String(req.body.note).trim() || null
    : null;
  if (!approve && !note) {
    return res.status(400).json({ error: 'Ret gerekçesi zorunludur' });
  }

  await execute(`
    UPDATE petty_cash_expenses
    SET status = ?, decided_by = ?, decision_note = ?,
        decided_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    WHERE id = ?
  `, next, req.user.id, note, row.id);

  await logActivity(req.user, approve ? 'PETTY_CASH_ONAY' : 'PETTY_CASH_RET',
    'petty_cash', row.id,
    `${row.amount} TL masraf ${approve ? 'onaylandı' : 'reddedildi'}: ${row.description}`
    + (note ? ` (${note})` : ''), row.store_id);

  const limit = await limitFor(row.store_id);
  const spent = await spentThisWeek(row.store_id);
  res.json({
    ok: true,
    status: next,
    remaining: Math.max(0, limit - spent.total),
  });
}

router.post('/:id/approve', requireRole(...APPROVER_ROLES), (req, res) => decide(req, res, 'approved'));
router.post('/:id/reject', requireRole(...APPROVER_ROLES), (req, res) => decide(req, res, 'rejected'));

// ---- Limitler (yalnizca Ana Yonetici belirler) ----

router.get('/limits', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const f = storeFilter(scope, 's.id');
  const rows = await queryAll(`
    SELECT s.id AS store_id, s.name AS store_name,
           COALESCE(l.weekly_amount, 0) AS weekly_amount, l.updated_at
    FROM stores s
    LEFT JOIN petty_cash_limits l ON l.store_id = s.id
    WHERE s.active = 1 ${f.sql}
    ORDER BY s.name
  `, ...f.params);
  res.json(rows.map((r) => ({ ...r, weekly_amount: Number(r.weekly_amount) })));
});

router.put('/limits/:storeId', requireRole('super_admin'), async (req, res) => {
  const storeId = Number(req.params.storeId);
  const store = await queryOne('SELECT id, name FROM stores WHERE id = ?', storeId);
  if (!store) return res.status(404).json({ error: 'Mağaza bulunamadı' });

  const value = Number(req.body && req.body.weekly_amount);
  if (!Number.isFinite(value) || value < 0) {
    return res.status(400).json({ error: 'Haftalık limit 0 veya daha büyük olmalıdır' });
  }

  await execute(`
    INSERT INTO petty_cash_limits (store_id, weekly_amount, updated_by)
    VALUES (?,?,?)
    ON CONFLICT (store_id) DO UPDATE SET
      weekly_amount = EXCLUDED.weekly_amount,
      updated_by = EXCLUDED.updated_by,
      updated_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  `, storeId, value, req.user.id);

  await logActivity(req.user, 'PETTY_CASH_LIMIT', 'store', storeId,
    `${store.name} haftalık petty cash limiti ${value} TL yapıldı`, storeId);
  res.json({ ok: true });
});

module.exports = router;
