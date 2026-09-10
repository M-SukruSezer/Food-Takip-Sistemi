const express = require('express');
const { queryAll, queryOne, execute, nowISO, addDays } = require('../db');
const { requireAuth, requireRole } = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

router.use(requireAuth);

// Onay listesi: mağaza yöneticisi kendi mağazası, super_admin tümü (?storeId=)
router.get('/', requireRole('super_admin', 'store_manager'), async (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  const params = [];
  let where = '';
  if (storeId) { where = ' WHERE a.store_id = ?'; params.push(storeId); }
  const status = req.query.status;
  if (status) {
    const allowed = ['pending', 'approved', 'rejected', 'cancelled'];
    const list = String(status).split(',').filter((s) => allowed.includes(s));
    if (list.length > 0) {
      where += where ? ' AND' : ' WHERE';
      where += ` a.status IN (${list.map(() => '?').join(',')})`;
      params.push(...list);
    }
  }

  const rows = await queryAll(`
    SELECT a.*,
      b.batch_code, b.remaining, b.quantity, b.status AS batch_status, b.thawing_finish_at,
      pt.name AS product_name, pt.skt_days,
      u.full_name AS requested_by_name,
      d.full_name AS decided_by_name,
      s.name AS store_name
    FROM transfer_approvals a
    JOIN batches b ON b.id = a.batch_id
    JOIN product_types pt ON pt.id = b.product_type_id
    LEFT JOIN users u ON u.id = a.requested_by
    LEFT JOIN users d ON d.id = a.decided_by
    LEFT JOIN stores s ON s.id = a.store_id
    ${where}
    ORDER BY a.requested_at DESC
    LIMIT 300
  `,...params);

  const now = Date.now();
  res.json(rows.map((r) => ({
    ...r,
    thaw_remaining_hours: r.thawing_finish_at
      ? Math.max(0, Math.ceil((new Date(r.thawing_finish_at).getTime() - now) / 3600000))
      : null,
  })));
});

// Onayla -> çözünmeden çıkar, food dolabına al (SKT başlar)
router.post('/:id/approve', requireRole('super_admin', 'store_manager'), async (req, res) => {
  const ap = await queryOne('SELECT * FROM transfer_approvals WHERE id = ?',Number(req.params.id));
  if (!ap) return res.status(404).json({ error: 'Onay isteği bulunamadı' });
  if (req.user.role !== 'super_admin' && ap.store_id !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu isteğe erişim yetkiniz yok' });
  }
  if (ap.status !== 'pending') return res.status(400).json({ error: 'Bu istek zaten karara bağlanmış' });

  const batch = await queryOne('SELECT * FROM batches WHERE id = ?',ap.batch_id);
  if (!batch) return res.status(404).json({ error: 'Ürün bulunamadı' });
  if (batch.status !== 'thawing') {
    await execute("UPDATE transfer_approvals SET status = 'cancelled', decided_by = ?, decided_at = ?, decision_note = ? WHERE id = ?",
      req.user.id, nowISO(), 'Ürün artık çözülme sürecinde değil', ap.id
    );
    return res.status(400).json({ error: 'Ürün artık çözülme sürecinde değil, istek iptal edildi' });
  }

  const type = await queryOne('SELECT * FROM product_types WHERE id = ?',batch.product_type_id);
  const cabinetAt = nowISO();
  const sktEnd = addDays(cabinetAt, type.skt_days);
  await execute(`
    UPDATE batches SET status = 'food_cabinet', food_cabinet_entered_at = ?, skt_end = ? WHERE id = ?
  `,cabinetAt, sktEnd, batch.id);
  await execute(`
    UPDATE transfer_approvals SET status = 'approved', decided_by = ?, decided_at = ?, decision_note = ? WHERE id = ?
  `,req.user.id, nowISO(), req.body.note || null, ap.id);

  await logActivity(req.user, 'TRANSFER_ONAY', 'batch', batch.id,
    `${type.name} erken aktarım onayı verildi, food dolabına alındı`, batch.store_id);
  res.json({ id: batch.id, skt_end: sktEnd });
});

// Reddet -> ürün çözülmede kalır
router.post('/:id/reject', requireRole('super_admin', 'store_manager'), async (req, res) => {
  const ap = await queryOne('SELECT * FROM transfer_approvals WHERE id = ?',Number(req.params.id));
  if (!ap) return res.status(404).json({ error: 'Onay isteği bulunamadı' });
  if (req.user.role !== 'super_admin' && ap.store_id !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu isteğe erişim yetkiniz yok' });
  }
  if (ap.status !== 'pending') return res.status(400).json({ error: 'Bu istek zaten karara bağlanmış' });

  await execute(`
    UPDATE transfer_approvals SET status = 'rejected', decided_by = ?, decided_at = ?, decision_note = ? WHERE id = ?
  `,req.user.id, nowISO(), req.body.note || null, ap.id);

  const batch = await queryOne('SELECT * FROM batches WHERE id = ?',ap.batch_id);
  const type = batch ? await queryOne('SELECT name FROM product_types WHERE id = ?',batch.product_type_id) : null;
  await logActivity(req.user, 'TRANSFER_RED', 'batch', ap.batch_id,
    `${type ? type.name : 'Ürün'} erken aktarım isteği reddedildi${req.body.note ? `: ${req.body.note}` : ''}`, ap.store_id);
  res.json({ ok: true });
});

module.exports = router;
