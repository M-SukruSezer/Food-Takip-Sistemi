const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth } = require('../auth');
const { batchRow } = require('../utils');

const router = express.Router();

router.use(requireAuth);

router.get('/', async (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (storeId && req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  const stats = async (sid) => {
    const w = sid ? 'AND store_id = ?' : '';
    const p = sid ? [sid] : [];
    const count = async (statusSql, extraParams = []) => await queryOne(statusSql, ...p, ...extraParams);
    return {
      frozen: await count(`SELECT COUNT(*) AS c, COALESCE(SUM(remaining),0) AS qty FROM batches WHERE status = 'frozen' ${w}`),
      thawing: await count(`SELECT COUNT(*) AS c, COALESCE(SUM(remaining),0) AS qty FROM batches WHERE status = 'thawing' ${w}`),
      food_cabinet: await count(`SELECT COUNT(*) AS c, COALESCE(SUM(remaining),0) AS qty FROM batches WHERE status = 'food_cabinet' ${w}`),
    };
  };

  const summary = await stats(storeId);
  const frozen = summary.frozen;
  const thawing = summary.thawing;
  const cabinet = summary.food_cabinet;

  // food dolabı ürünlerini çekip SKT durumunu dinamik hesapla
  let cabinetRows;
  if (storeId) {
    cabinetRows = await queryAll(`
      SELECT b.*, pt.name AS product_name, pt.skt_days FROM batches b
      JOIN product_types pt ON pt.id = b.product_type_id
      WHERE b.store_id = ? AND b.status = 'food_cabinet' AND b.skt_end IS NOT NULL
    `,storeId);
  } else {
    cabinetRows = await queryAll(`
      SELECT b.*, pt.name AS product_name, pt.skt_days FROM batches b
      JOIN product_types pt ON pt.id = b.product_type_id
      WHERE b.status = 'food_cabinet' AND b.skt_end IS NOT NULL
    `,);
  }
  const mapped = cabinetRows.map(batchRow);
  const expiring = mapped.filter(b => b.urgency === 'critical').reduce((s, b) => s + b.remaining, 0);
  const expired = mapped.filter(b => b.urgency === 'expired').reduce((s, b) => s + b.remaining, 0);
  const expiringCount = mapped.filter(b => b.urgency === 'critical' || b.urgency === 'warning').length;

  const today = new Date().toISOString().slice(0, 10);
  const soldToday = await queryOne(
    `SELECT COUNT(*) AS c, COALESCE(SUM(sl.quantity),0) AS qty, COALESCE(SUM(sl.quantity * sl.unit_price),0) AS revenue
     FROM sales sl WHERE sl.sold_at >= ? ${storeId ? 'AND sl.store_id = ?' : ''}`
  ,today + 'T00:00:00.000Z', ...(storeId ? [storeId] : []));

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
