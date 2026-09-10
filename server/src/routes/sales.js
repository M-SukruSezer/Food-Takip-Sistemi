const express = require('express');
const { db } = require('../db');
const { requireAuth, requireRole } = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

router.use(requireAuth);

router.get('/', (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (storeId && req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  const params = [];
  let where = '';
  if (storeId) { where = ' WHERE sl.store_id = ?'; params.push(storeId); }
  if (req.query.from) { where += where ? ' AND' : ' WHERE'; where += ' sl.sold_at >= ?'; params.push(req.query.from); }
  if (req.query.to) { where += where ? ' AND' : ' WHERE'; where += ' sl.sold_at <= ?'; params.push(req.query.to); }

  const rows = db.prepare(`
    SELECT sl.*, b.batch_code, pt.name AS product_name, u.full_name AS sold_by_name, s.name AS store_name
    FROM sales sl
    JOIN batches b ON b.id = sl.batch_id
    JOIN product_types pt ON pt.id = b.product_type_id
    LEFT JOIN users u ON u.id = sl.sold_by
    LEFT JOIN stores s ON s.id = sl.store_id
    ${where}
    ORDER BY sl.sold_at DESC
    LIMIT 500
  `).all(...params);
  res.json(rows);
});

router.post('/', requireRole('super_admin', 'store_manager', 'staff'), (req, res) => {
  const { batch_id, quantity, unit_price } = req.body || {};
  const batch = db.prepare('SELECT * FROM batches WHERE id = ?').get(Number(batch_id));
  if (!batch) return res.status(404).json({ error: 'Ürün bulunamadı' });
  if (req.user.role !== 'super_admin' && batch.store_id !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu ürüne erişim yetkiniz yok' });
  }
  if (batch.status !== 'food_cabinet') return res.status(400).json({ error: 'Ürün satışa uygun durumda değil' });
  const qty = Number(quantity);
  if (!Number.isInteger(qty) || qty < 1 || qty > batch.remaining) {
    return res.status(400).json({ error: `Geçersiz miktar. Kalan: ${batch.remaining}` });
  }
  const r = db.prepare(
    'INSERT INTO sales (store_id, batch_id, quantity, unit_price, sold_by) VALUES (?,?,?,?,?)'
  ).run(batch.store_id, batch.id, qty, unit_price || null, req.user.id);
  const remaining = batch.remaining - qty;
  db.prepare('UPDATE batches SET remaining = ?, status = ? WHERE id = ?').run(
    remaining, remaining === 0 ? 'sold' : 'food_cabinet', batch.id
  );
  const type = db.prepare('SELECT name FROM product_types WHERE id = ?').get(batch.product_type_id);
  logActivity(req.user, 'SATIS', 'batch', batch.id, `${type.name} ${qty} adet satıldı`, batch.store_id);
  res.status(201).json({ id: Number(r.lastInsertRowid), remaining, status: remaining === 0 ? 'sold' : 'food_cabinet' });
});

module.exports = router;
