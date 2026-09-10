const express = require('express');
const { db } = require('../db');
const { requireAuth } = require('../auth');

const router = express.Router();

router.use(requireAuth);

router.get('/', (req, res) => {
  let rows;
  if (req.user.role === 'super_admin') {
    rows = db.prepare(`
      SELECT l.*, s.name AS store_name FROM activity_logs l
      LEFT JOIN stores s ON s.id = l.store_id
      ORDER BY l.created_at DESC LIMIT 300
    `).all();
  } else {
    rows = db.prepare(`
      SELECT l.*, s.name AS store_name FROM activity_logs l
      LEFT JOIN stores s ON s.id = l.store_id
      WHERE l.store_id = ? ORDER BY l.created_at DESC LIMIT 300
    `).all(req.user.store_id);
  }
  res.json(rows);
});

module.exports = router;
