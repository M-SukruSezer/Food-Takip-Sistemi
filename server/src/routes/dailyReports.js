const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const {
  requireAuth, requireRole, resolveStoreScope, storeFilter, allowsStore,
} = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

// Rapor paneli yalnizca magazada vardiya yoneten iki role acik. Ust kademeler
// (Ana Yonetici, operations/regional manager) paneli hic gormez.
const ENTRY_ROLES = ['store_manager', 'shift_supervisor'];

router.use(requireAuth, requireRole(...ENTRY_ROLES));

// Kullanicinin girdigi ham alanlar. Oranlar burada yok: hesaplanir.
const FIELDS = [
  { key: 'net_sales', label: 'NET SALES', type: 'money' },
  { key: 'adt', label: 'ADT', type: 'int' },
  { key: 'product_qty', label: 'PRODUCT QTY', type: 'int' },
  { key: 'food_usd', label: 'FOOD USD', type: 'int' },
  { key: 'food_usd_try', label: 'FOOD USD ₺', type: 'money' },
  { key: 'food_mo_try', label: 'FOOD MO ₺', type: 'money' },
  { key: 'sold_beverage_qty', label: 'SOLD BEVERAGE QTY', type: 'int' },
  { key: 'modifiers', label: 'MODIFIERS', type: 'int' },
  { key: 'app_amount', label: 'APP', type: 'money' },
];

const INT_FIELDS = FIELDS.filter((f) => f.type === 'int').map((f) => f.key);

/// Sifira bolmeden oran: payda 0 ise null doner, arayuz "-" gosterir.
function ratio(a, b) {
  const x = Number(a) || 0;
  const y = Number(b) || 0;
  if (y === 0) return null;
  return x / y;
}

/// Ham verilerden turetilen olculer. Notlardaki tanimlar:
///   AT             = NET SALES / ADT
///   IPT            = (PRODUCT QTY - MODIFIERS) / ADT   (ekstralar haric)
///   FOOD MARKOUT % = FOOD MO ₺ / FOOD USD ₺
///   FOOD UPH       = FOOD USD / ADT * 100              (100 cekte ortalama)
///   MODIFIERS %    = MODIFIERS / SOLD BEVERAGE QTY
///   APP%           = APP / NET SALES
function derive(row) {
  const uph = ratio(row.food_usd, row.adt);
  return {
    at: ratio(row.net_sales, row.adt),
    ipt: ratio((Number(row.product_qty) || 0) - (Number(row.modifiers) || 0), row.adt),
    food_markout_pct: ratio(row.food_mo_try, row.food_usd_try),
    food_uph: uph === null ? null : uph * 100,
    modifiers_pct: ratio(row.modifiers, row.sold_beverage_qty),
    app_pct: ratio(row.app_amount, row.net_sales),
  };
}

function withMetrics(row) {
  const base = {};
  for (const f of FIELDS) base[f.key] = Number(row[f.key]) || 0;
  return { ...row, ...base, metrics: derive(base) };
}

/// Toplamlarda oranlar ortalamanin ortalamasi degil, TOPLANMIS ham verilerden
/// yeniden hesaplanir; aksi halde farkli gunlerin agirliklari kayboluyor.
function aggregate(rows) {
  const totals = {};
  for (const f of FIELDS) {
    totals[f.key] = rows.reduce((s, r) => s + (Number(r[f.key]) || 0), 0);
  }
  return { days: rows.length, totals, metrics: derive(totals) };
}

/// Donem baslangici. week: son 7 gun, month: son 30 gun.
function periodStart(period) {
  const days = period === 'week' ? 6 : 29;
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

/// Arayuz alan listesini buradan uretir; iki istemcide tekrar yazilmaz.
router.get('/fields', async (req, res) => {
  res.json({
    entry: FIELDS,
    derived: [
      { key: 'at', label: 'AT', type: 'money', formula: 'NET SALES / ADT' },
      { key: 'ipt', label: 'IPT', type: 'number', formula: '(PRODUCT QTY − MODIFIERS) / ADT' },
      { key: 'food_markout_pct', label: 'FOOD MARKOUT %', type: 'percent', formula: 'FOOD MO ₺ / FOOD USD ₺' },
      { key: 'food_uph', label: 'FOOD UPH', type: 'number', formula: 'FOOD USD / ADT × 100' },
      { key: 'modifiers_pct', label: 'MODIFIERS %', type: 'percent', formula: 'MODIFIERS / SOLD BEVERAGE QTY' },
      { key: 'app_pct', label: 'APP%', type: 'percent', formula: 'APP / NET SALES' },
    ],
  });
});

/// Gunluk kayitlar + donem ozeti.
router.get('/', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;

  const period = req.query.period === 'month' ? 'month' : 'week';
  const from = req.query.from || periodStart(period);
  const to = req.query.to || today();

  const f = storeFilter(scope, 'r.store_id');
  const rows = await queryAll(`
    SELECT r.*, s.name AS store_name, u.full_name AS created_by_name
    FROM daily_reports r
    LEFT JOIN stores s ON s.id = r.store_id
    LEFT JOIN users u ON u.id = r.created_by
    WHERE r.report_date >= ? AND r.report_date <= ? ${f.sql}
    ORDER BY r.report_date DESC, s.name
  `, from, to, ...f.params);

  const items = rows.map(withMetrics);
  res.json({ from, to, period, items, summary: aggregate(items) });
});

/// O gunun food rakamlarini sistemden hesaplar.
///
/// FOOD USD ve FOOD USD ₺ satislardan (kind = 'sale'), FOOD MO ₺ imhalardan
/// gelir. Ikram ikisine de girmez: satis degildir, zayi de degildir.
///
/// Imha satirlari fiyat anlik goruntusu tutmuyor, bu yuzden zayi tutari
/// cesidin GUNCEL fiyatiyla hesaplanir — hareket raporundaki ile ayni kural.
async function systemFoodValues(storeId, date) {
  const from = `${date}T00:00:00.000Z`;
  const to = `${date}T23:59:59.999Z`;

  const sold = await queryOne(`
    SELECT COALESCE(SUM(quantity),0) AS qty,
           COALESCE(SUM(quantity * unit_price),0) AS amount
    FROM sales
    WHERE kind = 'sale' AND store_id = ? AND sold_at >= ? AND sold_at <= ?
  `, storeId, from, to);

  const wasted = await queryOne(`
    SELECT COALESCE(SUM(d.quantity * pt.unit_price),0) AS amount,
           COALESCE(SUM(d.quantity),0) AS qty
    FROM discards d
    JOIN batches b ON b.id = d.batch_id
    JOIN product_types pt ON pt.id = b.product_type_id
    WHERE d.store_id = ? AND d.discarded_at >= ? AND d.discarded_at <= ?
  `, storeId, from, to);

  return {
    food_usd: Number(sold.qty) || 0,
    food_usd_try: Number(sold.amount) || 0,
    food_mo_try: Number(wasted.amount) || 0,
    // Arayuz "5 imha kaydindan" diye aciklama gosterebilsin.
    discarded_qty: Number(wasted.qty) || 0,
    // Imha tutari guncel fiyattan hesaplandi; arayuz bunu belirtir.
    waste_uses_current_price: true,
  };
}

/// Sistemden gelen food rakamlari — form bunlarla on dolar.
router.get('/suggested/:date', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const storeId = scope.storeId || req.user.store_id;
  if (!storeId) return res.status(400).json({ error: 'Mağaza belirtilmeli' });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(req.params.date)) {
    return res.status(400).json({ error: 'Tarih YYYY-AA-GG biçiminde olmalıdır' });
  }
  res.json(await systemFoodValues(storeId, req.params.date));
});

/// Tek gun (varsa) — giris formu mevcut degeri yuklesin diye.
router.get('/day/:date', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const storeId = scope.storeId || req.user.store_id;
  if (!storeId) return res.status(400).json({ error: 'Mağaza belirtilmeli' });

  const row = await queryOne(
    'SELECT * FROM daily_reports WHERE store_id = ? AND report_date = ?',
    storeId, req.params.date
  );
  // Kayit olsun olmasin sistem rakamlari birlikte doner; form food alanlarini
  // bununla on doldurur.
  const suggested = await systemFoodValues(storeId, req.params.date);
  res.json({ report: row ? withMetrics(row) : null, suggested });
});

/// Gunluk kayit ekle/guncelle. Ayni gun icin tekrar giris mevcut satiri gunceller.
router.post('/', requireRole(...ENTRY_ROLES), async (req, res) => {
  const storeId = req.user.store_id;
  if (!storeId) return res.status(403).json({ error: 'Size mağaza atanmamış' });

  const date = String((req.body && req.body.report_date) || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return res.status(400).json({ error: 'Tarih YYYY-AA-GG biçiminde olmalıdır' });
  }
  if (date > today()) {
    return res.status(400).json({ error: 'Gelecek tarihli rapor girilemez' });
  }

  const values = {};
  for (const field of FIELDS) {
    const raw = req.body ? req.body[field.key] : undefined;
    const n = Number(raw);
    if (raw === undefined || raw === null || raw === '' || !Number.isFinite(n) || n < 0) {
      return res.status(400).json({ error: `${field.label} 0 veya daha büyük bir sayı olmalıdır` });
    }
    // Adet alanlari tam sayi olmali; "3,5 fiş" gibi girisler engellenir.
    if (INT_FIELDS.includes(field.key) && !Number.isInteger(n)) {
      return res.status(400).json({ error: `${field.label} tam sayı olmalıdır` });
    }
    values[field.key] = n;
  }
  // Ekstralar toplam urunun parcasi; aksi halde IPT eksiye duser.
  if (values.modifiers > values.product_qty) {
    return res.status(400).json({ error: 'MODIFIERS, PRODUCT QTY değerinden büyük olamaz' });
  }

  const cols = FIELDS.map((f) => f.key);
  const r = await execute(`
    INSERT INTO daily_reports (store_id, report_date, ${cols.join(', ')}, created_by)
    VALUES (?,?,${cols.map(() => '?').join(',')},?)
    ON CONFLICT (store_id, report_date) DO UPDATE SET
      ${cols.map((c) => `${c} = EXCLUDED.${c}`).join(', ')},
      updated_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    RETURNING id
  `, storeId, date, ...cols.map((c) => values[c]), req.user.id);

  await logActivity(req.user, 'GUNLUK_RAPOR', 'daily_report', r.lastInsertRowid,
    `${date} günlük raporu kaydedildi (NET SALES ${values.net_sales} TL)`, storeId);
  res.status(201).json({ id: Number(r.lastInsertRowid), metrics: derive(values) });
});

router.delete('/:id', async (req, res) => {
  const row = await queryOne('SELECT * FROM daily_reports WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Rapor bulunamadı' });
  if (!allowsStore(req, row.store_id)) return res.status(403).json({ error: 'Bu rapora erişim yetkiniz yok' });
  await execute('DELETE FROM daily_reports WHERE id = ?', row.id);
  await logActivity(req.user, 'GUNLUK_RAPOR_SIL', 'daily_report', row.id,
    `${row.report_date} raporu silindi`, row.store_id);
  res.json({ ok: true });
});

module.exports = router;
