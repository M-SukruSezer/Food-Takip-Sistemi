const express = require('express');
const { db, nowISO, addHours, addDays } = require('../db');
const { requireAuth } = require('../auth');
const { logActivity, batchRow, requireStoreAccessForBatch } = require('../utils');

const router = express.Router();

router.use(requireAuth);

router.get('/', (req, res) => {
  const storeId = req.query.storeId ? Number(req.query.storeId) : req.user.store_id;
  if (!storeId) {
    if (req.user.role !== 'super_admin') return res.status(403).json({ error: 'Mağaza atanmamış' });
  } else if (req.user.role !== 'super_admin' && storeId !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }

  let where = '';
  const params = [];
  if (storeId) { where += ' WHERE b.store_id = ?'; params.push(storeId); }
  if (req.query.status) {
    const statuses = String(req.query.status).split(',');
    where += where ? ' AND' : ' WHERE';
    where += ` b.status IN (${statuses.map(() => '?').join(',')})`;
    params.push(...statuses);
  }

  const rows = db.prepare(`
    SELECT b.*, pt.name AS product_name, pt.skt_days, s.name AS store_name,
      (SELECT a.id FROM transfer_approvals a WHERE a.batch_id = b.id AND a.status = 'pending' LIMIT 1) AS pending_approval_id
    FROM batches b
    JOIN product_types pt ON pt.id = b.product_type_id
    LEFT JOIN stores s ON s.id = b.store_id
    ${where}
    ORDER BY b.created_at DESC
  `).all(...params);

  res.json(rows.map(batchRow));
});

router.get('/:id', (req, res) => {
  const row = db.prepare(`
    SELECT b.*, pt.name AS product_name, pt.skt_days, s.name AS store_name,
      (SELECT a.id FROM transfer_approvals a WHERE a.batch_id = b.id AND a.status = 'pending' LIMIT 1) AS pending_approval_id
    FROM batches b JOIN product_types pt ON pt.id = b.product_type_id LEFT JOIN stores s ON s.id = b.store_id
    WHERE b.id = ?
  `).get(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req.user);
  const sales = db.prepare(`
    SELECT sl.*, u.full_name AS sold_by_name FROM sales sl LEFT JOIN users u ON u.id = sl.sold_by WHERE sl.batch_id = ? ORDER BY sl.sold_at DESC
  `).all(row.id);
  res.json({ ...batchRow(row), sales });
});

// Yeni parti -> donuk depo
router.post('/', (req, res) => {
  const { product_type_id, quantity, batch_code, notes } = req.body || {};
  if (!product_type_id) return res.status(400).json({ error: 'Ürün çeşidi zorunludur' });
  const type = db.prepare('SELECT * FROM product_types WHERE id = ? AND active = 1').get(Number(product_type_id));
  if (!type) return res.status(404).json({ error: 'Ürün çeşidi bulunamadı' });
  let sid;
  if (req.user.role === 'super_admin') {
    sid = req.body.store_id ? Number(req.body.store_id) : type.store_id;
  } else {
    sid = req.user.store_id;
    // mağazaya özel çeşitler yalnızca kendi mağazasında, genel çeşitler her mağazada kullanılabilir
    if (type.store_id !== null && type.store_id !== sid) {
      return res.status(403).json({ error: 'Bu ürün çeşidi mağazanıza ait değil' });
    }
  }
  if (!sid) return res.status(400).json({ error: 'Mağaza seçimi zorunludur' });
  const qty = Number(quantity);
  if (!Number.isInteger(qty) || qty < 1) return res.status(400).json({ error: 'Miktar en az 1 olmalıdır' });

  const r = db.prepare(`
    INSERT INTO batches (store_id, product_type_id, batch_code, quantity, remaining, status, entered_frozen_at, created_by, notes)
    VALUES (?,?,?,?,?,'frozen',?,?,?)
  `).run(sid, type.id, batch_code || null, qty, qty, nowISO(), req.user.id, notes || null);

  logActivity(req.user, 'DONUK_EKLE', 'batch', r.lastInsertRowid,
    `${type.name} ${qty} adet donuk depoya eklendi${batch_code ? ` (${batch_code})` : ''}`, sid);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

// Çözülme sürecine başla (+4°C, 8 saat)
router.post('/:id/thaw', (req, res) => {
  const row = db.prepare('SELECT * FROM batches WHERE id = ?').get(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req.user);
  if (row.status !== 'frozen') return res.status(400).json({ error: 'Yalnızca donuk depodaki ürünler çözülme sürecine alınabilir' });

  let qty = row.remaining;
  if (req.body.quantity !== undefined && req.body.quantity !== '') {
    qty = Number(req.body.quantity);
  }
  if (!Number.isInteger(qty) || qty < 1) return res.status(400).json({ error: 'Miktar en az 1 olmalıdır' });
  if (qty > row.remaining) return res.status(400).json({ error: `Yeterli stok yok. Kalan: ${row.remaining}` });

  const start = nowISO();
  const finish = addHours(start, 8);
  const type = db.prepare('SELECT name FROM product_types WHERE id = ?').get(row.product_type_id);

  // tamamı alınıyorsa mevcut parti çözünmeye geçer
  if (qty >= row.remaining) {
    db.prepare(`
      UPDATE batches SET status = 'thawing', thawing_started_at = ?, thawing_finish_at = ? WHERE id = ?
    `).run(start, finish, row.id);
    logActivity(req.user, 'COZULME_BASLA', 'batch', row.id, `${type.name} (+4°C, 8 saat) çözülmeye alındı (${qty} adet)`, row.store_id);
    return res.json({ id: row.id, thawing_started_at: start, thawing_finish_at: finish });
  }

  // kısmi alınıyorsa parti bölünür: ayrılan adet yeni parti olarak çözünmeye gider, kalan donukta kalır
  const childCode = req.body.batch_code && String(req.body.batch_code).trim()
    ? String(req.body.batch_code).trim()
    : null;
  const r = db.prepare(`
    INSERT INTO batches (store_id, product_type_id, batch_code, quantity, remaining, status,
      entered_frozen_at, thawing_started_at, thawing_finish_at, notes, created_by)
    VALUES (?,?,?,?,?,'thawing',?,?,?,?,?)
  `).run(row.store_id, row.product_type_id, childCode, qty, qty, row.entered_frozen_at, start, finish, row.notes, req.user.id);
  const childId = Number(r.lastInsertRowid);
  db.prepare('UPDATE batches SET quantity = quantity - ?, remaining = remaining - ? WHERE id = ?').run(qty, qty, row.id);

  logActivity(req.user, 'COZULME_BASLA', 'batch', childId,
    `${type.name} (+4°C, 8 saat) çözülmeye alındı (${qty} adet)${childCode ? ` (${childCode})` : ''}`, row.store_id);
  logActivity(req.user, 'PARTI_BOLUNDU', 'batch', row.id,
    `${type.name} partisinden ${qty} adet çözünmeye ayrıldı, donukta ${row.remaining - qty} adet kaldı`, row.store_id);
  res.status(201).json({ id: childId, split: true, thawing_started_at: start, thawing_finish_at: finish });
});

// Çözülme tamamlandı -> food dolabına aktar (SKT başlar)
router.post('/:id/complete-thaw', (req, res) => {
  const row = db.prepare('SELECT * FROM batches WHERE id = ?').get(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req.user);
  if (row.status !== 'thawing') return res.status(400).json({ error: 'Bu ürün çözülme sürecinde değil' });
  if (!row.thawing_finish_at) return res.status(400).json({ error: 'Çözülme başlangıcı tanımsız' });

  const remainingMs = new Date(row.thawing_finish_at).getTime() - Date.now();
  if (remainingMs > 0) {
    const mins = Math.ceil(remainingMs / 60000);
    return res.status(400).json({ error: `Çözülme süresi tamamlanmadı. Kalan süre: ${mins} dakika` });
  }

  const type = db.prepare('SELECT * FROM product_types WHERE id = ?').get(row.product_type_id);
  const cabinetAt = nowISO();
  const sktEnd = addDays(cabinetAt, type.skt_days);
  db.prepare(`
    UPDATE batches SET status = 'food_cabinet', food_cabinet_entered_at = ?, skt_end = ? WHERE id = ?
  `).run(cabinetAt, sktEnd, row.id);

  logActivity(req.user, 'FOOD_DOLABI', 'batch', row.id,
    `${type.name} food dolabına aktarıldı, SKT: ${new Date(sktEnd).toLocaleString('tr-TR')}`, row.store_id);
  // varsa bekleyen erken-aktarım isteğini kapat (süre dolduğu için normal aktarım yapıldı)
  const cancelled = db.prepare("UPDATE transfer_approvals SET status = 'cancelled', decided_at = ?, decision_note = ? WHERE batch_id = ? AND status = 'pending'").run(
    nowISO(), 'Çözülme süresi dolduğu için normal aktarım yapıldı', row.id
  );
  if (cancelled.changes > 0) {
    logActivity(req.user, 'TRANSFER_IPTAL', 'batch', row.id, 'Bekleyen erken aktarım isteği kapatıldı', row.store_id);
  }
  res.json({ id: row.id, food_cabinet_entered_at: cabinetAt, skt_end: sktEnd });
});

// Erken food dolabı aktarımı için yönetici onayı iste
router.post('/:id/request-early-transfer', (req, res) => {
  const row = db.prepare('SELECT * FROM batches WHERE id = ?').get(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req.user);
  if (row.status !== 'thawing') return res.status(400).json({ error: 'Yalnızca çözülme sürecindeki ürünler için erken aktarım istenebilir' });
  if (row.thawing_finish_at && Date.now() >= new Date(row.thawing_finish_at).getTime()) {
    return res.status(400).json({ error: 'Çözülme süresi doldu, doğrudan food dolabına aktarabilirsiniz' });
  }
  const existing = db.prepare("SELECT id FROM transfer_approvals WHERE batch_id = ? AND status = 'pending'").get(row.id);
  if (existing) return res.status(400).json({ error: 'Bu ürün için zaten bekleyen bir onay isteği var' });
  const reason = req.body && req.body.reason ? String(req.body.reason).trim() : '';
  if (reason.length < 3) return res.status(400).json({ error: 'Erken aktarım nedeni yazılmalıdır' });

  const r = db.prepare(
    'INSERT INTO transfer_approvals (batch_id, store_id, requested_by, reason) VALUES (?,?,?,?)'
  ).run(row.id, row.store_id, req.user.id, reason);
  const type = db.prepare('SELECT name FROM product_types WHERE id = ?').get(row.product_type_id);
  logActivity(req.user, 'TRANSFER_ISTEK', 'batch', row.id,
    `${type.name} için erken food dolabı aktarımı istendi: ${reason}`, row.store_id);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

// İmha / atma
router.post('/:id/discard', (req, res) => {
  const row = db.prepare('SELECT * FROM batches WHERE id = ?').get(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req.user);
  if (!['frozen', 'thawing', 'food_cabinet'].includes(row.status)) {
    return res.status(400).json({ error: 'Bu durumdaki ürün imha edilemez' });
  }
  const { reason } = req.body || {};
  let qty = row.remaining;
  if (req.body.quantity !== undefined && req.body.quantity !== '') {
    qty = Number(req.body.quantity);
  }
  if (!Number.isInteger(qty) || qty < 1) return res.status(400).json({ error: 'Miktar en az 1 olmalıdır' });
  if (qty > row.remaining) return res.status(400).json({ error: `Yeterli stok yok. Kalan: ${row.remaining}` });

  const type = db.prepare('SELECT name FROM product_types WHERE id = ?').get(row.product_type_id);
  if (qty >= row.remaining) {
    db.prepare(`
      UPDATE batches SET status = 'discarded', discarded_at = ?, discard_reason = ?, remaining = 0 WHERE id = ?
    `).run(nowISO(), reason || 'Belirtilmedi', row.id);
    logActivity(req.user, 'IMHA', 'batch', row.id, `${type.name} tamamen imha edildi (${qty} adet, ${reason || 'sebep belirtilmedi'})`, row.store_id);
    db.prepare("UPDATE transfer_approvals SET status = 'cancelled', decided_at = ?, decision_note = ? WHERE batch_id = ? AND status = 'pending'").run(
      nowISO(), 'Ürün imha edildi', row.id
    );
    return res.json({ ok: true, remaining: 0, status: 'discarded' });
  }
  db.prepare('UPDATE batches SET remaining = remaining - ? WHERE id = ?').run(qty, row.id);
  logActivity(req.user, 'IMHA', 'batch', row.id, `${type.name} kısmi imha: ${qty} adet (${reason || 'sebep belirtilmedi'})`, row.store_id);
  res.json({ ok: true, remaining: row.remaining - qty, status: row.status });
});

// Donuk depodaki ürüne stok ekle (adetli)
router.post('/:id/add-stock', (req, res) => {
  const row = db.prepare('SELECT * FROM batches WHERE id = ?').get(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req.user);
  if (row.status !== 'frozen') return res.status(400).json({ error: 'Yalnızca donuk depodaki ürüne stok eklenebilir' });
  const qty = Number(req.body.quantity);
  if (!Number.isInteger(qty) || qty < 1) return res.status(400).json({ error: 'Miktar en az 1 olmalıdır' });
  db.prepare('UPDATE batches SET quantity = quantity + ?, remaining = remaining + ? WHERE id = ?').run(qty, qty, row.id);
  const type = db.prepare('SELECT name FROM product_types WHERE id = ?').get(row.product_type_id);
  logActivity(req.user, 'STOK_EKLE', 'batch', row.id, `${type.name} donuk stoka ${qty} adet eklendi`, row.store_id);
  res.json({ ok: true, quantity: row.quantity + qty, remaining: row.remaining + qty });
});

// Satış işaretleme
router.post('/:id/sell', (req, res) => {
  const row = db.prepare('SELECT * FROM batches WHERE id = ?').get(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req.user);
  if (row.status !== 'food_cabinet') return res.status(400).json({ error: 'Yalnızca food dolabındaki ürünler satılabilir' });
  if (row.skt_end && Date.now() > new Date(row.skt_end).getTime()) {
    return res.status(400).json({ error: 'Bu ürünün SKT süresi doldu, satış yapılamaz. İmha edilmelidir.' });
  }

  const qty = Number(req.body.quantity);
  if (!Number.isInteger(qty) || qty < 1) return res.status(400).json({ error: 'Miktar en az 1 olmalıdır' });
  if (qty > row.remaining) return res.status(400).json({ error: `Yeterli stok yok. Kalan: ${row.remaining}` });

  const unitPrice = req.body.unit_price !== undefined && req.body.unit_price !== '' ? Number(req.body.unit_price) : null;

  const newRemaining = row.remaining - qty;
  const newStatus = newRemaining === 0 ? 'sold' : row.status;
  const soldAt = nowISO();

  const r = db.prepare(
    'INSERT INTO sales (store_id, batch_id, quantity, unit_price, sold_at, sold_by) VALUES (?,?,?,?,?,?)'
  ).run(row.store_id, row.id, qty, unitPrice, soldAt, req.user.id);

  db.prepare('UPDATE batches SET remaining = ?, status = ?, sold_at = ? WHERE id = ?').run(
    newRemaining, newStatus, newStatus === 'sold' ? soldAt : row.sold_at, row.id
  );

  const type = db.prepare('SELECT name FROM product_types WHERE id = ?').get(row.product_type_id);
  logActivity(req.user, 'SATIS', 'batch', row.id, `${type.name} ${qty} adet satıldı${unitPrice ? ` (birim: ${unitPrice} TL)` : ''}`, row.store_id);
  res.status(201).json({ id: Number(r.lastInsertRowid), remaining: newRemaining, status: newStatus });
});

module.exports = router;
