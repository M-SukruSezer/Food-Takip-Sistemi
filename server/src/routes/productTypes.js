const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { requireAuth, requireRole } = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

router.use(requireAuth);

// Ürün çeşitleri: mağaza kullanıcıları genel çeşitler + kendi mağazasının çeşitlerini görür.
// Yazma (ekle/düzenle/sil) yalnızca Ana Yöneticiye aittir.
router.get('/', async (req, res) => {
  if (req.user.role === 'super_admin' && !req.query.storeId) {
    const rows = await queryAll(`
      SELECT pt.*, s.name AS store_name FROM product_types pt
      LEFT JOIN stores s ON s.id = pt.store_id ORDER BY pt.store_id IS NOT NULL, s.name, pt.name
    `,);
    return res.json(rows);
  }
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (!storeId) return res.status(400).json({ error: 'Mağaza zorunludur' });
  if (req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }
  const rows = await queryAll(`
    SELECT pt.*, s.name AS store_name FROM product_types pt
    LEFT JOIN stores s ON s.id = pt.store_id
    WHERE pt.store_id IS NULL OR pt.store_id = ?
    ORDER BY pt.store_id IS NOT NULL, pt.name
  `,storeId);
  res.json(rows);
});

router.post('/', requireRole('super_admin'), async (req, res) => {
  const { name, skt_days, description, store_id } = req.body || {};
  if (!name || !String(name).trim()) return res.status(400).json({ error: 'Ürün adı zorunludur' });
  const days = Number(skt_days);
  if (!Number.isInteger(days) || days < 1 || days > 14) {
    return res.status(400).json({ error: 'SKT süresi 1-14 gün arasında olmalıdır' });
  }
  // store_id boşsa genel çeşit (tüm mağazalar kullanabilir)
  const sid = store_id ? Number(store_id) : null;
  if (sid) {
    const store = await queryOne('SELECT id FROM stores WHERE id = ?',sid);
    if (!store) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  }

  const r = await execute('INSERT INTO product_types (store_id, name, skt_days, description) VALUES (?,?,?,?) RETURNING id',
    sid, String(name).trim(), days, description || null
  );
  await logActivity(req.user, 'CESIT_OLUSTUR', 'product_type', r.lastInsertRowid,
    `${name} (${days} gün SKT) eklendi${sid ? '' : ' [GENEL]'}`, sid);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

router.put('/:id', requireRole('super_admin'), async (req, res) => {
  const existing = await queryOne('SELECT * FROM product_types WHERE id = ?',Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Ürün çeşidi bulunamadı' });
  const { name, skt_days, description, active, store_id } = req.body || {};
  const days = skt_days !== undefined ? Number(skt_days) : existing.skt_days;
  if (!Number.isInteger(days) || days < 1 || days > 14) {
    return res.status(400).json({ error: 'SKT süresi 1-14 gün arasında olmalıdır' });
  }
  const sid = store_id === undefined ? existing.store_id : (store_id ? Number(store_id) : null);
  if (sid) {
    const store = await queryOne('SELECT id FROM stores WHERE id = ?',sid);
    if (!store) return res.status(404).json({ error: 'Mağaza bulunamadı' });
  }
  await execute('UPDATE product_types SET name = ?, skt_days = ?, description = ?, active = ?, store_id = ? WHERE id = ?',
    (name && String(name).trim()) || existing.name,
    days,
    description !== undefined ? description : existing.description,
    active === undefined ? existing.active : (active ? 1 : 0),
    sid,
    existing.id
  );
  await logActivity(req.user, 'CESIT_GUNCELLE', 'product_type', existing.id, `${existing.name} güncellendi`, sid);
  res.json({ ok: true });
});

router.delete('/:id', requireRole('super_admin'), async (req, res) => {
  const existing = await queryOne('SELECT * FROM product_types WHERE id = ?',Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Ürün çeşidi bulunamadı' });
  const used = Number((await queryOne('SELECT COUNT(*) AS c FROM batches WHERE product_type_id = ?', existing.id)).c);
  if (used > 0) {
    return res.status(400).json({ error: 'Bu çeşide ait ürün kayıtları var, silinemez. Pasife alabilirsiniz.' });
  }
  await execute('DELETE FROM product_types WHERE id = ?',existing.id);
  await logActivity(req.user, 'CESIT_SIL', 'product_type', existing.id, `${existing.name} silindi`, existing.store_id);
  res.json({ ok: true });
});

module.exports = router;
