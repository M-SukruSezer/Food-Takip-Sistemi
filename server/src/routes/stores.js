const express = require('express');
const { db } = require('../db');
const { requireAuth, requireRole } = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

router.use(requireAuth, requireRole('super_admin'));

router.get('/', (req, res) => {
  const rows = db.prepare(`
    SELECT s.*,
      (SELECT COUNT(*) FROM users u WHERE u.store_id = s.id AND u.active = 1) AS user_count,
      (SELECT COUNT(*) FROM batches b WHERE b.store_id = s.id AND b.status IN ('frozen','thawing','food_cabinet')) AS active_batch_count
    FROM stores s ORDER BY s.name
  `).all();
  res.json(rows);
});

router.get('/:id', (req, res) => {
  const row = db.prepare('SELECT * FROM stores WHERE id = ?').get(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  res.json(row);
});

router.post('/', (req, res) => {
  const { name, address, phone } = req.body || {};
  if (!name || !String(name).trim()) return res.status(400).json({ error: 'Mağaza adı zorunludur' });
  const r = db.prepare('INSERT INTO stores (name, address, phone) VALUES (?,?,?)').run(
    String(name).trim(), address || null, phone || null
  );
  logActivity(req.user, 'MAGAZA_OLUSTUR', 'store', r.lastInsertRowid, `${name} mağazası oluşturuldu`);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

router.put('/:id', (req, res) => {
  const { name, address, phone, active } = req.body || {};
  const existing = db.prepare('SELECT * FROM stores WHERE id = ?').get(Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  if (!name || !String(name).trim()) return res.status(400).json({ error: 'Mağaza adı zorunludur' });
  db.prepare('UPDATE stores SET name = ?, address = ?, phone = ?, active = ? WHERE id = ?').run(
    String(name).trim(), address || null, phone || null, active ? 1 : 0, existing.id
  );
  logActivity(req.user, 'MAGAZA_GUNCELLE', 'store', existing.id, `${name} güncellendi`);
  res.json({ ok: true });
});

router.delete('/:id', (req, res) => {
  const existing = db.prepare('SELECT * FROM stores WHERE id = ?').get(Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  const users = db.prepare('SELECT COUNT(*) AS c FROM users WHERE store_id = ?').get(existing.id).c;
  const batches = db.prepare('SELECT COUNT(*) AS c FROM batches WHERE store_id = ?').get(existing.id).c;
  if (users > 0 || batches > 0) {
    return res.status(400).json({ error: 'Mağazada kullanıcı veya ürün kaydı var, silinemez. Pasife alabilirsiniz.' });
  }
  db.prepare('DELETE FROM product_types WHERE store_id = ?').run(existing.id);
  db.prepare('DELETE FROM stores WHERE id = ?').run(existing.id);
  logActivity(req.user, 'MAGAZA_SIL', 'store', existing.id, `${existing.name} silindi`);
  res.json({ ok: true });
});

module.exports = router;
