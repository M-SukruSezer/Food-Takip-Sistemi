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

// Kullanicinin elle girdigi alanlar. Oranlar burada yok: hesaplanir.
const ENTRY_FIELDS = [
  { key: 'net_sales', label: 'NET SALES', type: 'money' },
  { key: 'adt', label: 'ADT', type: 'int' },
  { key: 'product_qty', label: 'PRODUCT QTY', type: 'int' },
  { key: 'sold_beverage_qty', label: 'SOLD BEVERAGE QTY', type: 'int' },
  { key: 'modifiers', label: 'MODIFIERS', type: 'int' },
  { key: 'app_amount', label: 'APP', type: 'money' },
];

// Food alanlari elle girilmez. Sistemdeki pasta satis ve zayi kayitlarindan
// hesaplanir, bu yuzden giris formunda yer almaz; formda yalnizca okunur
// bilgi olarak gosterilir.
const SYSTEM_FIELDS = [
  { key: 'food_usd', label: 'FOOD USD', type: 'int', source: 'Satis adedi (ikram haric)' },
  { key: 'food_usd_try', label: 'FOOD USD ₺', type: 'money', source: 'Satis tutari (ikram haric)' },
  { key: 'food_mo_try', label: 'FOOD MO ₺', type: 'money', source: 'Zayi tutari (guncel fiyat)' },
];

const ALL_FIELDS = [...ENTRY_FIELDS, ...SYSTEM_FIELDS];
const INT_FIELDS = ALL_FIELDS.filter((f) => f.type === 'int').map((f) => f.key);

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

/// Kayitli satiri olculerle donusturur.
///
/// `live` verilirse food alanlari o gunun GUNCEL sistem rakamlariyla degistirilir.
/// Boylece rapor kaydedildikten sonra gelen satis/zayi hareketleri de raporda
/// gorunur; kullanicinin kaydi yenilemesi gerekmez.
function withMetrics(row, live) {
  const base = {};
  for (const f of ALL_FIELDS) base[f.key] = Number(row[f.key]) || 0;
  if (live) {
    for (const f of SYSTEM_FIELDS) base[f.key] = Number(live[f.key]) || 0;
  }
  return { ...row, ...base, metrics: derive(base) };
}

/// Toplamlarda oranlar ortalamanin ortalamasi degil, TOPLANMIS ham verilerden
/// yeniden hesaplanir; aksi halde farkli gunlerin agirliklari kayboluyor.
function aggregate(rows) {
  const totals = {};
  for (const f of ALL_FIELDS) {
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

function isDate(s) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(s || ''));
}

/// Arayuz alan listesini buradan uretir; iki istemcide tekrar yazilmaz.
router.get('/fields', async (req, res) => {
  res.json({
    entry: ENTRY_FIELDS,
    // Formda gosterilmez, tabloda okunur olarak gosterilir.
    system: SYSTEM_FIELDS,
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

/// Bir tarih araligi icin gunluk food rakamlari: { 'YYYY-MM-DD': {...} }.
///
/// Gun gun sorgu atmak yerine iki gruplu sorgu kullanilir; 30 gunluk donemde
/// 60 sorgu yerine 2 sorgu yapilir.
async function systemFoodRange(storeId, from, to) {
  const start = `${from}T00:00:00.000Z`;
  const end = `${to}T23:59:59.999Z`;

  const sold = await queryAll(`
    SELECT substr(sold_at, 1, 10) AS d,
           COALESCE(SUM(quantity),0) AS qty,
           COALESCE(SUM(quantity * unit_price),0) AS amount
    FROM sales
    WHERE kind = 'sale' AND store_id = ? AND sold_at >= ? AND sold_at <= ?
    GROUP BY 1
  `, storeId, start, end);

  const wasted = await queryAll(`
    SELECT substr(d.discarded_at, 1, 10) AS d,
           COALESCE(SUM(d.quantity * pt.unit_price),0) AS amount,
           COALESCE(SUM(d.quantity),0) AS qty
    FROM discards d
    JOIN batches b ON b.id = d.batch_id
    JOIN product_types pt ON pt.id = b.product_type_id
    WHERE d.store_id = ? AND d.discarded_at >= ? AND d.discarded_at <= ?
    GROUP BY 1
  `, storeId, start, end);

  const out = {};
  const slot = (d) => (out[d] ||= {
    food_usd: 0, food_usd_try: 0, food_mo_try: 0,
    discarded_qty: 0, waste_uses_current_price: true,
  });
  for (const r of sold) {
    const s = slot(r.d);
    s.food_usd = Number(r.qty) || 0;
    s.food_usd_try = Number(r.amount) || 0;
  }
  for (const r of wasted) {
    const s = slot(r.d);
    s.food_mo_try = Number(r.amount) || 0;
    s.discarded_qty = Number(r.qty) || 0;
  }
  return out;
}

/// O gunun food rakamlarini sistemden hesaplar.
///
/// FOOD USD ve FOOD USD ₺ satislardan (kind = 'sale'), FOOD MO ₺ zayilardan
/// gelir. Ikram ikisine de girmez: satis degildir, zayi de degildir.
///
/// Zayi satirlari fiyat anlik goruntusu tutmuyor, bu yuzden zayi tutari
/// cesidin GUNCEL fiyatiyla hesaplanir — hareket raporundaki ile ayni kural.
async function systemFoodValues(storeId, date) {
  const map = await systemFoodRange(storeId, date, date);
  return map[date] || {
    food_usd: 0, food_usd_try: 0, food_mo_try: 0,
    discarded_qty: 0, waste_uses_current_price: true,
  };
}

/// Gunluk kayitlar + donem ozeti. Food alanlari canli sistem verisinden gelir.
router.get('/', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;

  const period = req.query.period === 'month' ? 'month' : 'week';
  const from = isDate(req.query.from) ? req.query.from : periodStart(period);
  const to = isDate(req.query.to) ? req.query.to : today();

  const f = storeFilter(scope, 'r.store_id');
  const rows = await queryAll(`
    SELECT r.*, s.name AS store_name, u.full_name AS created_by_name
    FROM daily_reports r
    LEFT JOIN stores s ON s.id = r.store_id
    LEFT JOIN users u ON u.id = r.created_by
    WHERE r.report_date >= ? AND r.report_date <= ? ${f.sql}
    ORDER BY r.report_date DESC, s.name
  `, from, to, ...f.params);

  // Tek magazaya daralmissa food alanlari canli veriyle tazelenir.
  const live = scope.storeId ? await systemFoodRange(scope.storeId, from, to) : null;
  const items = rows.map((r) => withMetrics(r, live ? live[r.report_date] : null));
  res.json({ from, to, period, items, summary: aggregate(items) });
});

/// Sistemden gelen food rakamlari — form bunlari okunur olarak gosterir.
router.get('/suggested/:date', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  const storeId = scope.storeId || req.user.store_id;
  if (!storeId) return res.status(400).json({ error: 'Mağaza belirtilmeli' });
  if (!isDate(req.params.date)) {
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
  if (!isDate(req.params.date)) {
    return res.status(400).json({ error: 'Tarih YYYY-AA-GG biçiminde olmalıdır' });
  }

  const row = await queryOne(
    'SELECT * FROM daily_reports WHERE store_id = ? AND report_date = ?',
    storeId, req.params.date
  );
  // Food alanlari elle girilmedigi icin her zaman sistemden gelir.
  const suggested = await systemFoodValues(storeId, req.params.date);
  res.json({ report: row ? withMetrics(row, suggested) : null, suggested });
});

/// Elle girilen alanlari dogrular. Hata varsa mesaj doner, yoksa null.
function readEntry(body) {
  const values = {};
  for (const field of ENTRY_FIELDS) {
    const raw = body ? body[field.key] : undefined;
    const n = Number(raw);
    if (raw === undefined || raw === null || raw === '' || !Number.isFinite(n) || n < 0) {
      return { error: `${field.label} 0 veya daha büyük bir sayı olmalıdır` };
    }
    // Adet alanlari tam sayi olmali; "3,5 fiş" gibi girisler engellenir.
    if (INT_FIELDS.includes(field.key) && !Number.isInteger(n)) {
      return { error: `${field.label} tam sayı olmalıdır` };
    }
    values[field.key] = n;
  }
  // Ekstralar toplam urunun parcasi; aksi halde IPT eksiye duser.
  if (values.modifiers > values.product_qty) {
    return { error: 'MODIFIERS, PRODUCT QTY değerinden büyük olamaz' };
  }
  return { values };
}

/// Kaydi yazar. Food alanlari istekten degil sistemden alinir.
async function saveDay(req, storeId, date, values) {
  const food = await systemFoodValues(storeId, date);
  const all = { ...values };
  for (const f of SYSTEM_FIELDS) all[f.key] = Number(food[f.key]) || 0;

  const cols = ALL_FIELDS.map((f) => f.key);
  const r = await execute(`
    INSERT INTO daily_reports (store_id, report_date, ${cols.join(', ')}, created_by)
    VALUES (?,?,${cols.map(() => '?').join(',')},?)
    ON CONFLICT (store_id, report_date) DO UPDATE SET
      ${cols.map((c) => `${c} = EXCLUDED.${c}`).join(', ')},
      updated_at = to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    RETURNING id
  `, storeId, date, ...cols.map((c) => all[c]), req.user.id);

  return { id: Number(r.lastInsertRowid), values: all, food };
}

/// Gunluk kayit ekle/guncelle. Ayni gun icin tekrar giris mevcut satiri gunceller.
router.post('/', async (req, res) => {
  const storeId = req.user.store_id;
  if (!storeId) return res.status(403).json({ error: 'Size mağaza atanmamış' });

  const date = String((req.body && req.body.report_date) || '').trim();
  if (!isDate(date)) {
    return res.status(400).json({ error: 'Tarih YYYY-AA-GG biçiminde olmalıdır' });
  }
  if (date > today()) {
    return res.status(400).json({ error: 'Gelecek tarihli rapor girilemez' });
  }

  const parsed = readEntry(req.body);
  if (parsed.error) return res.status(400).json({ error: parsed.error });

  const saved = await saveDay(req, storeId, date, parsed.values);
  await logActivity(req.user, 'GUNLUK_RAPOR', 'daily_report', saved.id,
    `${date} günlük raporu kaydedildi (NET SALES ${parsed.values.net_sales} TL)`, storeId);
  res.status(201).json({ id: saved.id, metrics: derive(saved.values), food: saved.food });
});

/// Kayitli gunu duzenle. Tarih degistirilemez; gun degisecekse silip yeniden
/// girmek gerekir, aksi halde ayni gune iki kayit cakismasi olusuyor.
router.put('/:id', async (req, res) => {
  const row = await queryOne('SELECT * FROM daily_reports WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Rapor bulunamadı' });
  if (!allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu rapora erişim yetkiniz yok' });
  }

  const parsed = readEntry(req.body);
  if (parsed.error) return res.status(400).json({ error: parsed.error });

  const saved = await saveDay(req, row.store_id, row.report_date, parsed.values);
  await logActivity(req.user, 'GUNLUK_RAPOR_GUNCELLE', 'daily_report', row.id,
    `${row.report_date} raporu güncellendi (NET SALES ${parsed.values.net_sales} TL)`, row.store_id);
  res.json({ id: saved.id, metrics: derive(saved.values), food: saved.food });
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
module.exports.ENTRY_FIELDS = ENTRY_FIELDS;
module.exports.SYSTEM_FIELDS = SYSTEM_FIELDS;
module.exports.ALL_FIELDS = ALL_FIELDS;
module.exports.derive = derive;
module.exports.systemFoodRange = systemFoodRange;
