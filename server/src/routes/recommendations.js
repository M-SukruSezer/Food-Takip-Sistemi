const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth, resolveStoreScope, storeFilter } = require('../auth');
const { batchRow, promoteReadyThawing } = require('../utils');

const router = express.Router();

router.use(requireAuth);

// Öneri satış listesi: food dolabındaki tüm ürünler, SKT'si en yakın olan en üstte.
// Aciliyet kademesi batchRow içinde hesaplanır: expired / critical (0-24 sa) /
// warning (24-48 sa) / normal (48 saatten fazla).
router.get('/', async (req, res) => {
  await promoteReadyThawing();
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;

  const f = storeFilter(scope, 'b.store_id');
  const where = " WHERE b.status = 'food_cabinet'" + f.sql;
  const params = [...f.params];

  const rows = await queryAll(`
    SELECT b.*, pt.name AS product_name, pt.skt_days, pt.unit_price AS product_unit_price, s.name AS store_name
    FROM batches b
    JOIN product_types pt ON pt.id = b.product_type_id
    LEFT JOIN stores s ON s.id = b.store_id
    ${where} AND b.skt_end IS NOT NULL AND b.remaining > 0
    ORDER BY b.skt_end ASC
  `,...params);

  const list = rows
    .map(batchRow)
    .filter(b => b.remaining_hours !== null)
    .map(b => ({
      ...b,
      remaining_hours: Math.max(0, b.remaining_hours),
      days_left: b.urgency === 'expired' ? 0 : Math.floor(b.remaining_hours / 24) + (b.remaining_hours % 24 > 0 ? 1 : 0),
    }));

  res.json(list);
});

module.exports = router;
