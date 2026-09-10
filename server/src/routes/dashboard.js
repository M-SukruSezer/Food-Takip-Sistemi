const express = require('express');
const { db } = require('../db');
const { requireAuth } = require('../auth');
const { batchRow } = require('../utils');

const router = express.Router();

router.use(requireAuth);

router.get('/', (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (storeId && req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  const stats = (sid) => {
    const w = sid ? 'AND store_id = ?' : '';
    const p = sid ? [sid] : [];
    const count = (statusSql, extraParams = []) => db.prepare(statusSql).get(...p, ...extraParams);
    return {
      frozen: count(`SELECT COUNT(*) AS c, COALESCE(SUM(remaining),0) AS qty FROM batches WHERE status = 'frozen' ${w}`),
      thawing: count(`SELECT COUNT(*) AS c, COALESCE(SUM(remaining),0) AS qty FROM batches WHERE status = 'thawing' ${w}`),
      food_cabinet: count(`SELECT COUNT(*) AS c, COALESCE(SUM(remaining),0) AS qty FROM batches WHERE status = 'food_cabinet' ${w}`),
    };
  };

  const frozen = stats(storeId).frozen;
  const thawing = stats(storeId).thawing;
  const cabinet = stats(storeId).food_cabinet;

  // food dolabı ürünlerini çekip SKT durumunu dinamik hesapla
  let cabinetRows;
  if (storeId) {
    cabinetRows = db.prepare(`
      SELECT b.*, pt.name AS product_name, pt.skt_days FROM batches b
      JOIN product_types pt ON pt.id = b.product_type_id
      WHERE b.store_id = ? AND b.status = 'food_cabinet' AND b.skt_end IS NOT NULL
    `).all(storeId);
  } else {
    cabinetRows = db.prepare(`
      SELECT b.*, pt.name AS product_name, pt.skt_days FROM batches b
      JOIN product_types pt ON pt.id = b.product_type_id
      WHERE b.status = 'food_cabinet' AND b.skt_end IS NOT NULL
    `).all();
  }
  const mapped = cabinetRows.map(batchRow);
  const expiring = mapped.filter(b => b.urgency === 'critical').reduce((s, b) => s + b.remaining, 0);
  const expired = mapped.filter(b => b.urgency === 'expired').reduce((s, b) => s + b.remaining, 0);
  const expiringCount = mapped.filter(b => b.urgency === 'critical' || b.urgency === 'warning').length;

  const today = new Date().toISOString().slice(0, 10);
  const soldToday = db.prepare(
    `SELECT COUNT(*) AS c, COALESCE(SUM(sl.quantity),0) AS qty, COALESCE(SUM(sl.quantity * sl.unit_price),0) AS revenue
     FROM sales sl WHERE sl.sold_at >= ? ${storeId ? 'AND sl.store_id = ?' : ''}`
  ).get(today + 'T00:00:00.000Z', ...(storeId ? [storeId] : []));

  res.json({
    counts: {
      frozen: frozen.c, frozen_qty: frozen.qty,
      thawing: thawing.c, thawing_qty: thawing.qty,
      food_cabinet: cabinet.c, food_cabinet_qty: cabinet.qty,
      expiring_qty: expiring,
      expired_qty: expired,
      expiring_count: expiringCount,
    },
    soldToday: { count: soldToday.c, qty: soldToday.qty, revenue: soldToday.revenue || 0 },
  });
});

module.exports = router;
