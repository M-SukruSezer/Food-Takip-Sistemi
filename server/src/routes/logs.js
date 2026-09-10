const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

router.use(requireAuth);

router.get('/', async (req, res) => {
  let rows;
  if (req.user.role === 'super_admin') {
    rows = await queryAll(`
      SELECT l.*, s.name AS store_name FROM activity_logs l
      LEFT JOIN stores s ON s.id = l.store_id
      ORDER BY l.created_at DESC LIMIT 300
    `,);
  } else {
    rows = await queryAll(`
      SELECT l.*, s.name AS store_name FROM activity_logs l
      LEFT JOIN stores s ON s.id = l.store_id
      WHERE l.store_id = ? ORDER BY l.created_at DESC LIMIT 300
    `,req.user.store_id);
  }
  res.json(rows);
});

module.exports = router;
