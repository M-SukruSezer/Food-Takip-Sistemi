const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth } = require('../auth');
const { batchRow } = require('../utils');

const router = express.Router();

router.use(requireAuth);

// Öneri satış listesi: food dolabında olan ve SKT'ye son 48 saat (2 gün) kalan ürünler.
// Sıralama: en acil (en erken dolan) önce.
router.get('/', async (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  const all = !storeId && req.user.role === 'super_admin';

  const where = all
    ? " WHERE b.status = 'food_cabinet'"
    : " WHERE b.status = 'food_cabinet' AND b.store_id = ?";
  const params = all ? [] : [storeId];

  const rows = await queryAll(`
    SELECT b.*, pt.name AS product_name, pt.skt_days, s.name AS store_name
    FROM batches b
    JOIN product_types pt ON pt.id = b.product_type_id
    LEFT JOIN stores s ON s.id = b.store_id
    ${where} AND b.skt_end IS NOT NULL
    ORDER BY b.skt_end ASC
  `,...params);

  const now = Date.now();
  const list = rows
    .map(batchRow)
    .filter(b => b.remaining_hours !== null && b.remaining_hours <= 48)
    .map(b => ({
      ...b,
      remaining_hours: Math.max(0, b.remaining_hours),
      days_left: b.urgency === 'expired' ? 0 : Math.floor(b.remaining_hours / 24) + (b.remaining_hours % 24 > 0 ? 1 : 0),
    }));

  res.json(list);
});

module.exports = router;
