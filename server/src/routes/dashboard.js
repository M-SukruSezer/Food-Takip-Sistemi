const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth, resolveStoreScope, storeFilter } = require('../auth');
const { batchRow, promoteReadyThawing } = require('../utils');

const router = express.Router();

router.use(requireAuth);

router.get('/', async (req, res) => {
  await promoteReadyThawing();
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;
  // Cok magazali rollerde storeId null kalir ama filtre bos kalmamali:
  // operations/regional manager yalnizca atandigi magazalari gormeli.
  const f = storeFilter(scope);

  const stats = async () => {
    const w = f.sql;
    const p = f.params;
    const count = async (statusSql, extraParams = []) => await queryOne(statusSql, ...p, ...extraParams);
    return {
      frozen: await count(`SELECT COUNT(*) AS c, COALESCE(SUM(remaining),0) AS qty FROM batches WHERE status = 'frozen' ${w}`),
      thawing: await count(`SELECT COUNT(*) AS c, COALESCE(SUM(remaining),0) AS qty FROM batches WHERE status = 'thawing' ${w}`),
      food_cabinet: await count(`SELECT COUNT(*) AS c, COALESCE(SUM(remaining),0) AS qty FROM batches WHERE status = 'food_cabinet' ${w}`),
    };
  };

  const summary = await stats();
  const frozen = summary.frozen;
  const thawing = summary.thawing;
  const cabinet = summary.food_cabinet;

  // food dolabı ürünlerini çekip SKT durumunu dinamik hesapla
  const cabinetFilter = storeFilter(scope, 'b.store_id');
  const cabinetRows = await queryAll(`
    SELECT b.*, pt.name AS product_name, pt.skt_days FROM batches b
    JOIN product_types pt ON pt.id = b.product_type_id
    WHERE b.status = 'food_cabinet' AND b.skt_end IS NOT NULL ${cabinetFilter.sql}
  `, ...cabinetFilter.params);
  const mapped = cabinetRows.map(batchRow);
  const expiring = mapped.filter(b => b.urgency === 'critical').reduce((s, b) => s + b.remaining, 0);
  const expired = mapped.filter(b => b.urgency === 'expired').reduce((s, b) => s + b.remaining, 0);
  const expiringCount = mapped.filter(b => b.urgency === 'critical' || b.urgency === 'warning').length;

  const today = new Date().toISOString().slice(0, 10);
  // kind = 'sale' filtresi: ikram stoktan duser ama ciroya ve satis adedine
  // girmez, ayri sayilir.
  const salesFilter = storeFilter(scope, 'sl.store_id');
  const soldToday = await queryOne(
    `SELECT COUNT(*) AS c, COALESCE(SUM(sl.quantity),0) AS qty, COALESCE(SUM(sl.quantity * sl.unit_price),0) AS revenue
     FROM sales sl WHERE sl.kind = 'sale' AND sl.sold_at >= ? ${salesFilter.sql}`
  ,today + 'T00:00:00.000Z', ...salesFilter.params);
  const ikramToday = await queryOne(
    `SELECT COUNT(*) AS c, COALESCE(SUM(sl.quantity),0) AS qty, COALESCE(SUM(sl.quantity * sl.unit_price),0) AS value
     FROM sales sl WHERE sl.kind = 'ikram' AND sl.sold_at >= ? ${salesFilter.sql}`
  ,today + 'T00:00:00.000Z', ...salesFilter.params);

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
    ikramToday: { count: ikramToday.c, qty: ikramToday.qty, value: ikramToday.value || 0 },
  });
});

module.exports = router;
