const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

router.use(requireAuth);

// Rapor: süper admin için tüm mağazaların özeti
router.get('/summary', async (req, res) => {
  if (req.user.role === 'super_admin') {
    const stores = await queryAll('SELECT id, name FROM stores WHERE active = 1 ORDER BY name');
    const summary = await Promise.all(stores.map(async (s) => {
      const active = await queryOne(`
        SELECT
          SUM(CASE WHEN status = 'frozen' THEN remaining ELSE 0 END) AS frozen_qty,
          SUM(CASE WHEN status = 'thawing' THEN remaining ELSE 0 END) AS thawing_qty,
          SUM(CASE WHEN status = 'food_cabinet' THEN remaining ELSE 0 END) AS cabinet_qty,
          SUM(CASE WHEN status = 'discarded' THEN remaining ELSE 0 END) AS discarded_qty
        FROM batches WHERE store_id = ?
      `,s.id);
      const sold = await queryOne(`
        SELECT COALESCE(SUM(quantity),0) AS qty, COALESCE(SUM(quantity * unit_price),0) AS revenue,
               COUNT(*) AS count FROM sales WHERE store_id = ?
      `,s.id);
      const productCount = Number((await queryOne('SELECT COUNT(*) AS c FROM product_types WHERE store_id = ?', s.id)).c);
      return {
        id: s.id, name: s.name,
        frozen_qty: active.frozen_qty || 0,
        thawing_qty: active.thawing_qty || 0,
        cabinet_qty: active.cabinet_qty || 0,
        discarded_qty: active.discarded_qty || 0,
        sold_qty: sold.qty, revenue: sold.revenue || 0, sold_count: sold.count,
        product_count: productCount,
      };
    }));
    return res.json({ type: 'multi', stores: summary });
  }

  // mağaza kullanıcısı: kendi özeti
  const sid = req.user.store_id;
  const store = await queryOne('SELECT id, name FROM stores WHERE id = ?',sid);
  const active = await queryOne(`
    SELECT
      SUM(CASE WHEN status = 'frozen' THEN remaining ELSE 0 END) AS frozen_qty,
      SUM(CASE WHEN status = 'thawing' THEN remaining ELSE 0 END) AS thawing_qty,
      SUM(CASE WHEN status = 'food_cabinet' THEN remaining ELSE 0 END) AS cabinet_qty,
      SUM(CASE WHEN status = 'discarded' THEN remaining ELSE 0 END) AS discarded_qty,
      SUM(CASE WHEN status = 'sold' THEN remaining ELSE 0 END) AS sold_qty
    FROM batches WHERE store_id = ?
  `,sid);
  const sold = await queryOne(
    'SELECT COALESCE(SUM(quantity),0) AS qty, COALESCE(SUM(quantity * unit_price),0) AS revenue, COUNT(*) AS count FROM sales WHERE store_id = ?'
  ,sid);
  const productCount = Number((await queryOne('SELECT COUNT(*) AS c FROM product_types WHERE store_id = ?', sid)).c);

  res.json({
    type: 'single',
    store,
    frozen_qty: active.frozen_qty || 0,
    thawing_qty: active.thawing_qty || 0,
    cabinet_qty: active.cabinet_qty || 0,
    discarded_qty: active.discarded_qty || 0,
    sold_qty: sold.qty, revenue: sold.revenue || 0, sold_count: sold.count,
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
      FROM sales WHERE sold_at >= ? AND sold_at <= ? ${storeId ? 'AND store_id = ?' : ''}
    `, start, end, ...(storeId ? [storeId] : []));
    return { date: day, qty: row.qty, revenue: row.revenue || 0 };
  }));
  res.json(data);
});

module.exports = router;
