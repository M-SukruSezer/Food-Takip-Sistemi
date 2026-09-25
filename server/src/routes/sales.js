const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth, requireRole, resolveStoreScope, allowsStore, storeFilter, ROLES } = require('../auth');
const { requirePermission } = require('../auth');
const { logActivity } = require('../utils');
const { readQuantity, correctRecord, deleteRecord } = require('./corrections');

const router = express.Router();

router.use(requireAuth);

router.get('/', async (req, res) => {
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;

  const f = storeFilter(scope, 'sl.store_id');
  const params = [...f.params];
  // storeFilter " AND ..." uretir; ilk kosul oldugu icin WHERE'e cevrilir.
  let where = f.sql ? ' WHERE' + f.sql.slice(4) : '';
  // ?kind=sale|ikram ile tek tur listelenebilir; verilmezse ikisi de gelir.
  if (req.query.kind === 'sale' || req.query.kind === 'ikram') {
    where += where ? ' AND' : ' WHERE';
    where += ' sl.kind = ?';
    params.push(req.query.kind);
  }
  if (req.query.from) { where += where ? ' AND' : ' WHERE'; where += ' sl.sold_at >= ?'; params.push(req.query.from); }
  if (req.query.to) { where += where ? ' AND' : ' WHERE'; where += ' sl.sold_at <= ?'; params.push(req.query.to); }

  const rows = await queryAll(`
    SELECT sl.*, b.batch_code, pt.name AS product_name, u.full_name AS sold_by_name, s.name AS store_name
    FROM sales sl
    JOIN batches b ON b.id = sl.batch_id
    JOIN product_types pt ON pt.id = b.product_type_id
    LEFT JOIN users u ON u.id = sl.sold_by
    LEFT JOIN stores s ON s.id = sl.store_id
    ${where}
    ORDER BY sl.sold_at DESC
    LIMIT 500
  `,...params);
  res.json(rows);
});

router.post('/', requireRole(...ROLES), async (req, res) => {
  const { batch_id, quantity } = req.body || {};
  const batch = await queryOne('SELECT * FROM batches WHERE id = ?',Number(batch_id));
  if (!batch) return res.status(404).json({ error: 'Ürün bulunamadı' });
  if (!allowsStore(req, batch.store_id)) {
    return res.status(403).json({ error: 'Bu ürüne erişim yetkiniz yok' });
  }
  if (batch.status !== 'food_cabinet') return res.status(400).json({ error: 'Ürün satışa uygun durumda değil' });
  const qty = Number(quantity);
  if (!Number.isInteger(qty) || qty < 1 || qty > batch.remaining) {
    return res.status(400).json({ error: `Geçersiz miktar. Kalan: ${batch.remaining}` });
  }
  // Birim fiyat pasta cesidinden gelir; satirda anlik goruntusu saklanir.
  const type = await queryOne('SELECT name, unit_price FROM product_types WHERE id = ?',batch.product_type_id);
  const unitPrice = type && type.unit_price !== null && type.unit_price !== undefined ? Number(type.unit_price) : null;

  const r = await execute(
    'INSERT INTO sales (store_id, batch_id, quantity, unit_price, sold_by) VALUES (?,?,?,?,?) RETURNING id'
  ,batch.store_id, batch.id, qty, unitPrice, req.user.id);
  const remaining = batch.remaining - qty;
  await execute('UPDATE batches SET remaining = ?, status = ? WHERE id = ?',
    remaining, remaining === 0 ? 'sold' : 'food_cabinet', batch.id
  );
  await logActivity(req.user, 'SATIS', 'batch', batch.id,
    `${type.name} ${qty} adet satıldı${unitPrice !== null ? ` (birim: ${unitPrice} TL, tutar: ${qty * unitPrice} TL)` : ' (fiyat tanımlı değil)'}`, batch.store_id);
  res.status(201).json({
    id: Number(r.lastInsertRowid), remaining, status: remaining === 0 ? 'sold' : 'food_cabinet',
    unit_price: unitPrice, total: unitPrice !== null ? qty * unitPrice : null,
  });
});

/// Satis veya ikram kaydinin adedini duzeltir.
///
/// Adet azaltilirsa fark partinin stoguna geri doner, artirilirsa stoktan
/// dusulur. Rapor paneli food rakamlarini satislardan canli hesapladigi icin
/// duzeltme gecmis gunlerin raporuna da yansir.
router.put('/:id', requirePermission('adjust_batches'), async (req, res) => {
  const sale = await queryOne('SELECT * FROM sales WHERE id = ?', Number(req.params.id));
  if (!sale) return res.status(404).json({ error: 'Kayıt bulunamadı' });
  if (!allowsStore(req, sale.store_id)) {
    return res.status(403).json({ error: 'Bu kayda erişim yetkiniz yok' });
  }
  const parsed = readQuantity(req.body && req.body.quantity);
  if (parsed.error) return res.status(400).json({ error: parsed.error });
  if (parsed.quantity === sale.quantity) return res.json({ ok: true, unchanged: true });

  const batch = await queryOne('SELECT * FROM batches WHERE id = ?', sale.batch_id);
  if (!batch) return res.status(404).json({ error: 'Ürün bulunamadı' });

  const out = await correctRecord({
    table: 'sales', record: sale, batch, newQuantity: parsed.quantity, req,
  });
  if (out.error) return res.status(400).json({ error: out.error });

  const type = await queryOne(
    'SELECT pt.name FROM product_types pt JOIN batches b ON b.product_type_id = pt.id WHERE b.id = ?',
    sale.batch_id
  );
  const label = sale.kind === 'ikram' ? 'İkram' : 'Satış';
  await logActivity(req.user, 'SATIS_DUZELT', 'sale', sale.id,
    `${type.name} ${label} adedi düzeltildi: ${sale.quantity} -> ${parsed.quantity}`
    + (out.delta > 0 ? ` (${out.delta} adet stoka döndü)` : out.delta < 0 ? ` (${-out.delta} adet stoktan düştü)` : ''),
    sale.store_id);
  res.json({ ok: true, quantity: parsed.quantity, ...out });
});

/// Satis veya ikram kaydini siler; adedin tamami stoga doner.
router.delete('/:id', requirePermission('adjust_batches'), async (req, res) => {
  const sale = await queryOne('SELECT * FROM sales WHERE id = ?', Number(req.params.id));
  if (!sale) return res.status(404).json({ error: 'Kayıt bulunamadı' });
  if (!allowsStore(req, sale.store_id)) {
    return res.status(403).json({ error: 'Bu kayda erişim yetkiniz yok' });
  }
  const batch = await queryOne('SELECT * FROM batches WHERE id = ?', sale.batch_id);
  if (!batch) return res.status(404).json({ error: 'Ürün bulunamadı' });

  const type = await queryOne(
    'SELECT pt.name FROM product_types pt JOIN batches b ON b.product_type_id = pt.id WHERE b.id = ?',
    sale.batch_id
  );
  await deleteRecord({ table: 'sales', record: sale, batch });
  const label = sale.kind === 'ikram' ? 'İkram' : 'Satış';
  await logActivity(req.user, 'SATIS_SIL', 'sale', sale.id,
    `${type.name} ${label} kaydı silindi (${sale.quantity} adet stoka döndü)`, sale.store_id);
  res.json({ ok: true });
});

module.exports = router;
