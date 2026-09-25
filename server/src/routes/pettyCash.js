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

async function spentThisWeek(storeId) {
  const row = await queryOne(
    'SELECT COALESCE(SUM(amount),0) AS total FROM petty_cash_expenses WHERE store_id = ? AND spent_at >= ?',
    storeId, weekStart()
  );
  return Number(row.total) || 0;
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
           (e.receipt IS NOT NULL) AS has_receipt,
           u.full_name AS created_by_name, s.name AS store_name
    FROM petty_cash_expenses e
    LEFT JOIN users u ON u.id = e.created_by
    LEFT JOIN stores s ON s.id = e.store_id
    ${where}
    ORDER BY e.spent_at DESC
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
      spent_this_week: spent,
      remaining: Math.max(0, limit - spent),
      week_start: weekStart(),
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
  const remaining = limit - spent;
  if (value > remaining) {
    return res.status(400).json({
      error: `Haftalık limit aşılıyor. Kalan: ${remaining.toFixed(2)} TL`,
    });
  }

  const r = await execute(
    `INSERT INTO petty_cash_expenses (store_id, amount, description, receipt, spent_at, created_by)
     VALUES (?,?,?,?,COALESCE(?, to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),?)
     RETURNING id`,
    storeId, value, String(description).trim(), receipt || null, spent_at || null, req.user.id
  );
  await logActivity(req.user, 'PETTY_CASH', 'petty_cash', r.lastInsertRowid,
    `${value} TL masraf: ${String(description).trim()}`, storeId);

  res.status(201).json({
    id: Number(r.lastInsertRowid),
    remaining: remaining - value,
  });
});

/// Masraf silme: kaydi giren kisi ya da Ana Yonetici.
router.delete('/:id', async (req, res) => {
  const row = await queryOne('SELECT * FROM petty_cash_expenses WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Masraf bulunamadı' });
  if (!allowsStore(req, row.store_id)) return res.status(403).json({ error: 'Bu masrafa erişim yetkiniz yok' });
  if (req.user.role !== 'super_admin' && row.created_by !== req.user.id) {
    return res.status(403).json({ error: 'Yalnızca kendi girdiğiniz masrafı silebilirsiniz' });
  }
  await execute('DELETE FROM petty_cash_expenses WHERE id = ?', row.id);
  await logActivity(req.user, 'PETTY_CASH_SIL', 'petty_cash', row.id,
    `${row.amount} TL masraf silindi`, row.store_id);
  res.json({ ok: true });
});

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
