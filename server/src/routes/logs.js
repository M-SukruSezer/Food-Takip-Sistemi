const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth, resolveStoreScope, storeFilter } = require('../auth');

const router = express.Router();

router.use(requireAuth);

router.get('/', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;

  const f = storeFilter(scope, 'l.store_id');
  const where = f.sql ? ' WHERE' + f.sql.slice(4) : '';
  const rows = await queryAll(`
    SELECT l.*, s.name AS store_name FROM activity_logs l
    LEFT JOIN stores s ON s.id = l.store_id
    ${where}
    ORDER BY l.created_at DESC LIMIT 300
  `, ...f.params);
  res.json(rows);
});

module.exports = router;
