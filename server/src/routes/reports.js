const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

router.use(requireAuth);

// Rapor: süper admin için tüm mağazaların özeti
router.get('/summary', async (req, res) => {
  const requested = req.query.storeId ? Number(req.query.storeId) : null;
  if (requested && req.user.role !== 'super_admin' && requested !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  // Ana yönetici mağaza seçmediyse tüm mağazaların karşılaştırmalı özeti döner.
  if (req.user.role === 'super_admin' && !requested) {
    const stores = await queryAll('SELECT id, name FROM stores WHERE active = 1 ORDER BY name');
    const summary = await Promise.all(stores.map(async (s) => {
      const active = await queryOne(`
        SELECT
          SUM(CASE WHEN status = 'frozen' THEN remaining ELSE 0 END) AS frozen_qty,
          SUM(CASE WHEN status = 'thawing' THEN remaining ELSE 0 END) AS thawing_qty,
          SUM(CASE WHEN status = 'food_cabinet' THEN remaining ELSE 0 END) AS cabinet_qty,
          0 AS unused_discarded
        FROM batches WHERE store_id = ?
      `,s.id);
      const wasted = await queryOne('SELECT COALESCE(SUM(quantity),0) AS qty FROM discards WHERE store_id = ?', s.id);
      const sold = await queryOne(`
        SELECT COALESCE(SUM(quantity),0) AS qty, COALESCE(SUM(quantity * unit_price),0) AS revenue,
               COUNT(*) AS count FROM sales WHERE kind = 'sale' AND store_id = ?
      `,s.id);
      const ikram = await queryOne(
        "SELECT COALESCE(SUM(quantity),0) AS qty FROM sales WHERE kind = 'ikram' AND store_id = ?", s.id);
      const productCount = Number((await queryOne('SELECT COUNT(*) AS c FROM product_types WHERE store_id = ? AND active = 1', s.id)).c);
      return {
        id: s.id, name: s.name,
        frozen_qty: active.frozen_qty || 0,
        thawing_qty: active.thawing_qty || 0,
        cabinet_qty: active.cabinet_qty || 0,
        discarded_qty: wasted.qty || 0,
        sold_qty: sold.qty, revenue: sold.revenue || 0, sold_count: sold.count,
        ikram_qty: ikram.qty || 0,
        product_count: productCount,
      };
    }));
    return res.json({ type: 'multi', stores: summary });
  }

  // tek mağaza özeti: seçilen mağaza ya da kullanıcının kendi mağazası
  const sid = requested || req.user.store_id;
  const store = await queryOne('SELECT id, name FROM stores WHERE id = ?',sid);
  const active = await queryOne(`
    SELECT
      SUM(CASE WHEN status = 'frozen' THEN remaining ELSE 0 END) AS frozen_qty,
      SUM(CASE WHEN status = 'thawing' THEN remaining ELSE 0 END) AS thawing_qty,
      SUM(CASE WHEN status = 'food_cabinet' THEN remaining ELSE 0 END) AS cabinet_qty,
      SUM(CASE WHEN status = 'sold' THEN remaining ELSE 0 END) AS sold_qty
    FROM batches WHERE store_id = ?
  `,sid);
  const wasted = await queryOne('SELECT COALESCE(SUM(quantity),0) AS qty FROM discards WHERE store_id = ?', sid);
  const sold = await queryOne(
    "SELECT COALESCE(SUM(quantity),0) AS qty, COALESCE(SUM(quantity * unit_price),0) AS revenue, COUNT(*) AS count FROM sales WHERE kind = 'sale' AND store_id = ?"
  ,sid);
  const ikram = await queryOne(
    "SELECT COALESCE(SUM(quantity),0) AS qty FROM sales WHERE kind = 'ikram' AND store_id = ?", sid);
  const productCount = Number((await queryOne('SELECT COUNT(*) AS c FROM product_types WHERE store_id = ? AND active = 1', sid)).c);

  res.json({
    type: 'single',
    store,
    frozen_qty: active.frozen_qty || 0,
    thawing_qty: active.thawing_qty || 0,
    cabinet_qty: active.cabinet_qty || 0,
    discarded_qty: wasted.qty || 0,
    sold_qty: sold.qty, revenue: sold.revenue || 0, sold_count: sold.count,
    ikram_qty: ikram.qty || 0,
    product_count: productCount,
  });
});

// Son 7 gün satış grafiği verisi
router.get('/sales7', async (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (storeId && req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  const days = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date(Date.now() - i * 86400000);
    days.push(d.toISOString().slice(0, 10));
  }

  const data = await Promise.all(days.map(async (day) => {
    const start = day + 'T00:00:00.000Z';
    const end = day + 'T23:59:59.999Z';
    const row = await queryOne(`
      SELECT COALESCE(SUM(quantity),0) AS qty, COALESCE(SUM(quantity * unit_price),0) AS revenue
      FROM sales WHERE kind = 'sale' AND sold_at >= ? AND sold_at <= ? ${storeId ? 'AND store_id = ?' : ''}
    `, start, end, ...(storeId ? [storeId] : []));
    return { date: day, qty: row.qty, revenue: row.revenue || 0 };
  }));
  res.json(data);
});

// Stok dagilimi (durum bazinda kalan adet)
router.get('/status', async (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (storeId && req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu magazaya erisim yetkiniz yok' });
  }
  // Satis ve imha adetleri batches.remaining'den okunamaz: satilan ya da imha
  // edilen partide remaining 0'a duser, bu yuzden eski sorgu "Satildi" ve
  // "Imha" icin her zaman 0 donuyordu. Aktif stok remaining'den, satis/ikram
  // sales tablosundan, imha discards tablosundan sayilir.
  const where = storeId ? 'WHERE store_id = ?' : '';
  const args = storeId ? [storeId] : [];

  const active = await queryAll(`
    SELECT status, COALESCE(SUM(remaining),0) AS quantity
    FROM batches ${where ? where + " AND" : "WHERE"} status IN ('frozen','thawing','food_cabinet')
    GROUP BY status
  `, ...args);

  const moved = await queryAll(`
    SELECT CASE WHEN kind = 'ikram' THEN 'ikram' ELSE 'sold' END AS status,
           COALESCE(SUM(quantity),0) AS quantity
    FROM sales ${where}
    GROUP BY 1
  `, ...args);

  const discarded = await queryOne(
    `SELECT COALESCE(SUM(quantity),0) AS quantity FROM discards ${where}`, ...args
  );

  const byStatus = new Map();
  for (const key of ['frozen', 'thawing', 'food_cabinet', 'sold', 'ikram', 'discarded']) {
    byStatus.set(key, 0);
  }
  for (const r of [...active, ...moved]) byStatus.set(r.status, Number(r.quantity) || 0);
  byStatus.set('discarded', Number(discarded.quantity) || 0);

  // Sifir olanlar grafigi kalabaliklastirmasin; hepsi sifirsa bos liste doner
  // ve arayuz "veri bulunamadi" der.
  const rows = [...byStatus.entries()]
    .filter(([, quantity]) => quantity > 0)
    .map(([status, quantity]) => ({ status, quantity }))
    .sort((a, b) => b.quantity - a.quantity);
  res.json(rows);
});

// Son hareketler akisi
router.get('/activity', async (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (storeId && req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu magazaya erisim yetkiniz yok' });
  }
  const rows = await queryAll(`
    SELECT l.action, l.details, l.created_at, s.name AS store_name
    FROM activity_logs l LEFT JOIN stores s ON s.id = l.store_id
    ${storeId ? 'WHERE l.store_id = ?' : ''}
    ORDER BY l.created_at DESC LIMIT 20
  `, ...(storeId ? [storeId] : []));
  res.json(rows);
});

// Urun performansi: haftanin ve ayin en cok / en az satan urunleri ve
// en cok zayi verilenler. Tam siralanmis listeler doner; ilk/son kac tanesinin
// gosterilecegine arayuz karar verir.
router.get('/products', async (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (storeId && req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  const since = (days) => new Date(Date.now() - days * 24 * 3600 * 1000).toISOString();

  const sold = (from) => queryAll(`
    SELECT pt.id, pt.name,
           COALESCE(SUM(sl.quantity),0) AS qty,
           COALESCE(SUM(sl.quantity * sl.unit_price),0) AS revenue
    FROM sales sl
    JOIN batches b ON b.id = sl.batch_id
    JOIN product_types pt ON pt.id = b.product_type_id
    WHERE sl.kind = 'sale' AND sl.sold_at >= ? ${storeId ? 'AND sl.store_id = ?' : ''}
    GROUP BY pt.id, pt.name
    ORDER BY qty DESC, pt.name
  `, ...(storeId ? [from, storeId] : [from]));

  const wasted = (from) => queryAll(`
    SELECT pt.id, pt.name, COALESCE(SUM(d.quantity),0) AS qty
    FROM discards d
    JOIN batches b ON b.id = d.batch_id
    JOIN product_types pt ON pt.id = b.product_type_id
    WHERE d.discarded_at >= ? ${storeId ? 'AND d.store_id = ?' : ''}
    GROUP BY pt.id, pt.name
    ORDER BY qty DESC, pt.name
  `, ...(storeId ? [from, storeId] : [from]));

  const build = async (days) => {
    const from = since(days);
    return { from, days, sold: await sold(from), wasted: await wasted(from) };
  };

  res.json({ week: await build(7), month: await build(30) });
});

// Hareket raporu: satis, ikram ve imha kayitlarini tek listede birlestirir.
// Filtreler: tarih araligi, urun cesidi, hareket turu, magaza.
//
// Imha satirlarinda tutar yoktur (discards tablosu fiyat anlik goruntusu
// tutmuyor); cesidin GUNCEL fiyatiyla hesaplanir ve arayuz bunu boyle yazar.
router.get('/movements', async (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (storeId && req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  const allowedKinds = ['sale', 'ikram', 'discard'];
  const kinds = String(req.query.kind || '')
    .split(',')
    .map((k) => k.trim())
    .filter((k) => allowedKinds.includes(k));
  const wanted = kinds.length > 0 ? kinds : allowedKinds;

  const productTypeId = req.query.productTypeId ? Number(req.query.productTypeId) : null;
  // Tarihler gun bazinda gelir (YYYY-MM-DD); bitis gunu tamamen dahil olsun.
  const from = req.query.from ? `${req.query.from}T00:00:00.000Z` : null;
  const to = req.query.to ? `${req.query.to}T23:59:59.999Z` : null;

  const salesKinds = wanted.filter((k) => k !== 'discard');
  const parts = [];
  const params = [];

  if (salesKinds.length > 0) {
    let where = `WHERE sl.kind IN (${salesKinds.map(() => '?').join(',')})`;
    params.push(...salesKinds);
    if (storeId) { where += ' AND sl.store_id = ?'; params.push(storeId); }
    if (productTypeId) { where += ' AND b.product_type_id = ?'; params.push(productTypeId); }
    if (from) { where += ' AND sl.sold_at >= ?'; params.push(from); }
    if (to) { where += ' AND sl.sold_at <= ?'; params.push(to); }
    parts.push(`
      SELECT sl.id, sl.kind, sl.quantity, sl.unit_price, sl.sold_at AS at,
             b.product_type_id, b.batch_code, pt.name AS product_name,
             u.full_name AS user_name, s.name AS store_name, NULL AS reason
      FROM sales sl
      JOIN batches b ON b.id = sl.batch_id
      JOIN product_types pt ON pt.id = b.product_type_id
      LEFT JOIN users u ON u.id = sl.sold_by
      LEFT JOIN stores s ON s.id = sl.store_id
      ${where}
    `);
  }

  if (wanted.includes('discard')) {
    let where = 'WHERE 1 = 1';
    if (storeId) { where += ' AND d.store_id = ?'; params.push(storeId); }
    if (productTypeId) { where += ' AND b.product_type_id = ?'; params.push(productTypeId); }
    if (from) { where += ' AND d.discarded_at >= ?'; params.push(from); }
    if (to) { where += ' AND d.discarded_at <= ?'; params.push(to); }
    parts.push(`
      SELECT d.id, 'discard' AS kind, d.quantity, pt.unit_price, d.discarded_at AS at,
             b.product_type_id, b.batch_code, pt.name AS product_name,
             u.full_name AS user_name, s.name AS store_name, d.reason
      FROM discards d
      JOIN batches b ON b.id = d.batch_id
      JOIN product_types pt ON pt.id = b.product_type_id
      LEFT JOIN users u ON u.id = d.discarded_by
      LEFT JOIN stores s ON s.id = d.store_id
      ${where}
    `);
  }

  if (parts.length === 0) {
    return res.json({ items: [], totals: emptyTotals() });
  }

  const rows = await queryAll(
    `SELECT * FROM (${parts.join(' UNION ALL ')}) m ORDER BY m.at DESC LIMIT 1000`,
    ...params
  );

  const items = rows.map((r) => ({
    ...r,
    // Satis/ikram satirinda fiyat anlik goruntudur, imhada guncel fiyattir.
    total: r.unit_price === null || r.unit_price === undefined ? null : Number(r.unit_price) * r.quantity,
    price_is_current: r.kind === 'discard',
  }));

  const sum = (kind, field) => items
    .filter((i) => i.kind === kind)
    .reduce((acc, i) => acc + (field === 'quantity' ? i.quantity : (i.total || 0)), 0);

  res.json({
    items,
    totals: {
      sale_qty: sum('sale', 'quantity'),
      revenue: sum('sale', 'total'),
      ikram_qty: sum('ikram', 'quantity'),
      ikram_value: sum('ikram', 'total'),
      discard_qty: sum('discard', 'quantity'),
      discard_value: sum('discard', 'total'),
      count: items.length,
    },
  });
});

function emptyTotals() {
  return {
    sale_qty: 0, revenue: 0, ikram_qty: 0, ikram_value: 0,
    discard_qty: 0, discard_value: 0, count: 0,
  };
}

module.exports = router;
