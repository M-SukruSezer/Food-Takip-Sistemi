const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth, requireRole } = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

router.use(requireAuth, requireRole('super_admin'));

router.get('/', async (req, res) => {
  const rows = await queryAll(`
    SELECT s.*,
      (SELECT COUNT(*) FROM users u WHERE u.store_id = s.id AND u.active = 1) AS user_count,
      (SELECT COUNT(*) FROM batches b WHERE b.store_id = s.id AND b.status IN ('frozen','thawing','food_cabinet')) AS active_batch_count
    FROM stores s ORDER BY s.name
  `,);
  res.json(rows);
});

router.get('/:id', async (req, res) => {
  const row = await queryOne('SELECT * FROM stores WHERE id = ?',Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  res.json(row);
});

router.post('/', async (req, res) => {
  const { name, address, phone } = req.body || {};
  if (!name || !String(name).trim()) return res.status(400).json({ error: 'Mağaza adı zorunludur' });
  const r = await execute('INSERT INTO stores (name, address, phone) VALUES (?,?,?) RETURNING id',
    String(name).trim(), address || null, phone || null
  );
  await logActivity(req.user, 'MAGAZA_OLUSTUR', 'store', r.lastInsertRowid, `${name} mağazası oluşturuldu`);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

router.put('/:id', async (req, res) => {
  const { name, address, phone, active } = req.body || {};
  const existing = await queryOne('SELECT * FROM stores WHERE id = ?',Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  if (!name || !String(name).trim()) return res.status(400).json({ error: 'Mağaza adı zorunludur' });
  await execute('UPDATE stores SET name = ?, address = ?, phone = ?, active = ? WHERE id = ?',
    String(name).trim(), address || null, phone || null, active ? 1 : 0, existing.id
  );
  await logActivity(req.user, 'MAGAZA_GUNCELLE', 'store', existing.id, `${name} güncellendi`);
  res.json({ ok: true });
});

router.delete('/:id', async (req, res) => {
  const existing = await queryOne('SELECT * FROM stores WHERE id = ?',Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  const users = Number((await queryOne('SELECT COUNT(*) AS c FROM users WHERE store_id = ?', existing.id)).c);
  const batches = Number((await queryOne('SELECT COUNT(*) AS c FROM batches WHERE store_id = ?', existing.id)).c);
  if (users > 0 || batches > 0) {
    return res.status(400).json({ error: 'Mağazada kullanıcı veya ürün kaydı var, silinemez. Pasife alabilirsiniz.' });
  }
  await execute('DELETE FROM product_types WHERE store_id = ?',existing.id);
  await execute('DELETE FROM stores WHERE id = ?',existing.id);
  await logActivity(req.user, 'MAGAZA_SIL', 'store', existing.id, `${existing.name} silindi`);
  res.json({ ok: true });
});

module.exports = router;
