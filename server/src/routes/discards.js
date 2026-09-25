const express = require('express');
const { queryAll, queryOne } = require('../db');
const {
  requireAuth, requirePermission, resolveStoreScope, storeFilter, allowsStore,
} = require('../auth');
const { logActivity } = require('../utils');
const { readQuantity, correctRecord, deleteRecord } = require('./corrections');

const router = express.Router();

router.use(requireAuth);

/// Zayi kayitlari. Hareket raporundan farki: tek tek duzeltilebilsin diye
/// kayit kimligi ve parti bilgisiyle birlikte doner.
router.get('/', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;

  const f = storeFilter(scope, 'd.store_id');
  const params = [...f.params];
  let where = f.sql ? ' WHERE' + f.sql.slice(4) : '';
  if (req.query.from) { where += where ? ' AND' : ' WHERE'; where += ' d.discarded_at >= ?'; params.push(req.query.from); }
  if (req.query.to) { where += where ? ' AND' : ' WHERE'; where += ' d.discarded_at <= ?'; params.push(req.query.to); }

  const rows = await queryAll(`
    SELECT d.*, b.batch_code, b.status AS batch_status,
           pt.name AS product_name, pt.unit_price,
           u.full_name AS discarded_by_name, s.name AS store_name
    FROM discards d
    JOIN batches b ON b.id = d.batch_id
    JOIN product_types pt ON pt.id = b.product_type_id
    LEFT JOIN users u ON u.id = d.discarded_by
    LEFT JOIN stores s ON s.id = d.store_id
    ${where}
    ORDER BY d.discarded_at DESC
    LIMIT 500
  `, ...params);
  res.json(rows);
});

/// Zayi adedini duzeltir. Azaltilirsa fark stoga geri doner.
///
/// Rapor panelindeki FOOD MO ₺ zayi kayitlarindan canli hesaplandigi icin
/// duzeltme gecmis gunlerin raporuna da yansir.
router.put('/:id', requirePermission('adjust_batches'), async (req, res) => {
  const row = await queryOne('SELECT * FROM discards WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Kayıt bulunamadı' });
  if (!allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu kayda erişim yetkiniz yok' });
  }
  const parsed = readQuantity(req.body && req.body.quantity);
  if (parsed.error) return res.status(400).json({ error: parsed.error });

  const reason = req.body && req.body.reason !== undefined
    ? String(req.body.reason).trim() || 'Belirtilmedi'
    : row.reason;
  if (parsed.quantity === row.quantity && reason === row.reason) {
    return res.json({ ok: true, unchanged: true });
  }

  const batch = await queryOne('SELECT * FROM batches WHERE id = ?', row.batch_id);
  if (!batch) return res.status(404).json({ error: 'Ürün bulunamadı' });

  const out = await correctRecord({
    table: 'discards', record: row, batch, newQuantity: parsed.quantity, req,
    extra: { reason },
  });
  if (out.error) return res.status(400).json({ error: out.error });

  const type = await queryOne(
    'SELECT pt.name FROM product_types pt JOIN batches b ON b.product_type_id = pt.id WHERE b.id = ?',
    row.batch_id
  );
  await logActivity(req.user, 'ZAYI_DUZELT', 'discard', row.id,
    `${type.name} zayi adedi düzeltildi: ${row.quantity} -> ${parsed.quantity}`
    + (out.delta > 0 ? ` (${out.delta} adet stoka döndü)` : out.delta < 0 ? ` (${-out.delta} adet stoktan düştü)` : ''),
    row.store_id);
  res.json({ ok: true, quantity: parsed.quantity, reason, ...out });
});

/// Zayi kaydini siler; adedin tamami stoga doner.
router.delete('/:id', requirePermission('adjust_batches'), async (req, res) => {
  const row = await queryOne('SELECT * FROM discards WHERE id = ?', Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Kayıt bulunamadı' });
  if (!allowsStore(req, row.store_id)) {
    return res.status(403).json({ error: 'Bu kayda erişim yetkiniz yok' });
  }
  const batch = await queryOne('SELECT * FROM batches WHERE id = ?', row.batch_id);
  if (!batch) return res.status(404).json({ error: 'Ürün bulunamadı' });

  const type = await queryOne(
    'SELECT pt.name FROM product_types pt JOIN batches b ON b.product_type_id = pt.id WHERE b.id = ?',
    row.batch_id
  );
  await deleteRecord({ table: 'discards', record: row, batch });
  await logActivity(req.user, 'ZAYI_SIL', 'discard', row.id,
    `${type.name} zayi kaydı silindi (${row.quantity} adet stoka döndü)`, row.store_id);
  res.json({ ok: true });
});

module.exports = router;
