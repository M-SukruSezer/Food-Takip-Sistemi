const express = require('express');
const { queryAll, queryOne, execute, transaction, nowISO, addHours, addDays } = require('../db');
const { requireAuth, requirePermission, permissionsOf, resolveStoreScope, storeFilter } = require('../auth');
const { logActivity, batchRow, requireStoreAccessForBatch, promoteReadyThawing } = require('../utils');

const router = express.Router();

router.use(requireAuth);

router.get('/', async (req, res) => {
  await promoteReadyThawing();
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;

  const f = storeFilter(scope, 'b.store_id');
  const params = [...f.params];
  // storeFilter " AND ..." uretir; ilk kosul oldugu icin WHERE'e cevrilir.
  let where = f.sql ? ' WHERE' + f.sql.slice(4) : '';
  if (req.query.status) {
    const statuses = String(req.query.status).split(',');
    where += where ? ' AND' : ' WHERE';
    where += ` b.status IN (${statuses.map(() => '?').join(',')})`;
    params.push(...statuses);
  }

  const rows = await queryAll(`
    SELECT b.*, pt.name AS product_name, pt.skt_days, pt.unit_price AS product_unit_price, s.name AS store_name,
      (SELECT a.id FROM transfer_approvals a WHERE a.batch_id = b.id AND a.status = 'pending' LIMIT 1) AS pending_approval_id
    FROM batches b
    JOIN product_types pt ON pt.id = b.product_type_id
    LEFT JOIN stores s ON s.id = b.store_id
    ${where}
    ORDER BY b.created_at DESC
  `,...params);

  res.json(rows.map(batchRow));
});

router.get('/:id', async (req, res) => {
  await promoteReadyThawing();
  const row = await queryOne(`
    SELECT b.*, pt.name AS product_name, pt.skt_days, pt.unit_price AS product_unit_price, s.name AS store_name,
      (SELECT a.id FROM transfer_approvals a WHERE a.batch_id = b.id AND a.status = 'pending' LIMIT 1) AS pending_approval_id
    FROM batches b JOIN product_types pt ON pt.id = b.product_type_id LEFT JOIN stores s ON s.id = b.store_id
    WHERE b.id = ?
  `,Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req);
  const sales = await queryAll(`
    SELECT sl.*, u.full_name AS sold_by_name FROM sales sl LEFT JOIN users u ON u.id = sl.sold_by WHERE sl.batch_id = ? ORDER BY sl.sold_at DESC
  `,row.id);
  res.json({ ...batchRow(row), sales });
});

// Yeni parti -> donuk depo
router.post('/', async (req, res) => {
  const { product_type_id, quantity, batch_code, notes } = req.body || {};
  if (!product_type_id) return res.status(400).json({ error: 'Ürün çeşidi zorunludur' });
  const type = await queryOne('SELECT * FROM product_types WHERE id = ? AND active = 1',Number(product_type_id));
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

  const r = await execute(`
    INSERT INTO batches (store_id, product_type_id, batch_code, quantity, remaining, status, entered_frozen_at, created_by, notes)
    VALUES (?,?,?,?,?,'frozen',?,?,?) RETURNING id
  `,sid, type.id, batch_code || null, qty, qty, nowISO(), req.user.id, notes || null);

  await logActivity(req.user, 'DONUK_EKLE', 'batch', r.lastInsertRowid,
    `${type.name} ${qty} adet donuk depoya eklendi${batch_code ? ` (${batch_code})` : ''}`, sid);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

// Çözülme sürecine başla (+4°C, 8 saat)
router.post('/:id/thaw', async (req, res) => {
  const row = await queryOne('SELECT * FROM batches WHERE id = ?',Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req);
  if (row.status !== 'frozen') return res.status(400).json({ error: 'Yalnızca donuk depodaki ürünler çözülme sürecine alınabilir' });

  let qty = row.remaining;
  if (req.body.quantity !== undefined && req.body.quantity !== '') {
    qty = Number(req.body.quantity);
  }
  if (!Number.isInteger(qty) || qty < 1) return res.status(400).json({ error: 'Miktar en az 1 olmalıdır' });
  if (qty > row.remaining) return res.status(400).json({ error: `Yeterli stok yok. Kalan: ${row.remaining}` });

  const start = nowISO();
  const finish = addHours(start, 8);
  const type = await queryOne('SELECT name FROM product_types WHERE id = ?',row.product_type_id);

  // tamamı alınıyorsa mevcut parti çözünmeye geçer
  if (qty >= row.remaining) {
    await execute(`
      UPDATE batches SET status = 'thawing', thawing_started_at = ?, thawing_finish_at = ? WHERE id = ?
    `,start, finish, row.id);
    await logActivity(req.user, 'COZULME_BASLA', 'batch', row.id, `${type.name} (+4°C, 8 saat) çözülmeye alındı (${qty} adet)`, row.store_id);
    return res.json({ id: row.id, thawing_started_at: start, thawing_finish_at: finish });
  }

  // kısmi alınıyorsa parti bölünür: ayrılan adet yeni parti olarak çözünmeye gider, kalan donukta kalır
  const childCode = req.body.batch_code && String(req.body.batch_code).trim()
    ? String(req.body.batch_code).trim()
    : null;
  const r = await execute(`
    INSERT INTO batches (store_id, product_type_id, batch_code, quantity, remaining, status,
      entered_frozen_at, thawing_started_at, thawing_finish_at, notes, created_by)
    VALUES (?,?,?,?,?,'thawing',?,?,?,?,?) RETURNING id
  `,row.store_id, row.product_type_id, childCode, qty, qty, row.entered_frozen_at, start, finish, row.notes, req.user.id);
  const childId = Number(r.lastInsertRowid);
  await execute('UPDATE batches SET quantity = quantity - ?, remaining = remaining - ? WHERE id = ?',qty, qty, row.id);

  await logActivity(req.user, 'COZULME_BASLA', 'batch', childId,
    `${type.name} (+4°C, 8 saat) çözülmeye alındı (${qty} adet)${childCode ? ` (${childCode})` : ''}`, row.store_id);
  await logActivity(req.user, 'PARTI_BOLUNDU', 'batch', row.id,
    `${type.name} partisinden ${qty} adet çözünmeye ayrıldı, donukta ${row.remaining - qty} adet kaldı`, row.store_id);
  res.status(201).json({ id: childId, split: true, thawing_started_at: start, thawing_finish_at: finish });
});

// Çözülme tamamlandı -> food dolabına aktar (SKT başlar)
router.post('/:id/complete-thaw', async (req, res) => {
  const row = await queryOne('SELECT * FROM batches WHERE id = ?',Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req);
  if (row.status !== 'thawing') return res.status(400).json({ error: 'Bu ürün çözülme sürecinde değil' });
  if (!row.thawing_finish_at) return res.status(400).json({ error: 'Çözülme başlangıcı tanımsız' });

  const remainingMs = new Date(row.thawing_finish_at).getTime() - Date.now();
  if (remainingMs > 0) {
    const mins = Math.ceil(remainingMs / 60000);
    return res.status(400).json({ error: `Çözülme süresi tamamlanmadı. Kalan süre: ${mins} dakika` });
  }

  const type = await queryOne('SELECT * FROM product_types WHERE id = ?',row.product_type_id);
  // SKT, dugmeye basildigi an degil cozulmenin bittigi an baslar.
  const cabinetAt = row.thawing_finish_at;
  const sktEnd = addDays(cabinetAt, type.skt_days);
  await execute(`
    UPDATE batches SET status = 'food_cabinet', food_cabinet_entered_at = ?, skt_end = ? WHERE id = ?
  `,cabinetAt, sktEnd, row.id);

  await logActivity(req.user, 'FOOD_DOLABI', 'batch', row.id,
    `${type.name} food dolabına aktarıldı, SKT: ${new Date(sktEnd).toLocaleString('tr-TR')}`, row.store_id);
  // varsa bekleyen erken-aktarım isteğini kapat (süre dolduğu için normal aktarım yapıldı)
  const cancelled = await execute("UPDATE transfer_approvals SET status = 'cancelled', decided_at = ?, decision_note = ? WHERE batch_id = ? AND status = 'pending'",
    nowISO(), 'Çözülme süresi dolduğu için normal aktarım yapıldı', row.id
  );
  if (cancelled.changes > 0) {
    await logActivity(req.user, 'TRANSFER_IPTAL', 'batch', row.id, 'Bekleyen erken aktarım isteği kapatıldı', row.store_id);
  }
  res.json({ id: row.id, food_cabinet_entered_at: cabinetAt, skt_end: sktEnd });
});

// Erken food dolabı aktarımı için yönetici onayı iste
router.post('/:id/request-early-transfer', async (req, res) => {
  const row = await queryOne('SELECT * FROM batches WHERE id = ?',Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req);
  if (row.status !== 'thawing') return res.status(400).json({ error: 'Yalnızca çözülme sürecindeki ürünler için erken aktarım istenebilir' });
  if (row.thawing_finish_at && Date.now() >= new Date(row.thawing_finish_at).getTime()) {
    return res.status(400).json({ error: 'Çözülme süresi doldu, doğrudan food dolabına aktarabilirsiniz' });
  }
  const existing = await queryOne("SELECT id FROM transfer_approvals WHERE batch_id = ? AND status = 'pending'",row.id);
  if (existing) return res.status(400).json({ error: 'Bu ürün için zaten bekleyen bir onay isteği var' });
  const reason = req.body && req.body.reason ? String(req.body.reason).trim() : '';
  if (reason.length < 3) return res.status(400).json({ error: 'Erken aktarım nedeni yazılmalıdır' });

  const r = await execute(
    'INSERT INTO transfer_approvals (batch_id, store_id, requested_by, reason) VALUES (?,?,?,?) RETURNING id'
  ,row.id, row.store_id, req.user.id, reason);
  const type = await queryOne('SELECT name FROM product_types WHERE id = ?',row.product_type_id);
  await logActivity(req.user, 'TRANSFER_ISTEK', 'batch', row.id,
    `${type.name} için erken food dolabı aktarımı istendi: ${reason}`, row.store_id);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

// İmha / atma
router.post('/:id/discard', requirePermission('discard'), async (req, res) => {
  const row = await queryOne('SELECT * FROM batches WHERE id = ?',Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req);
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

  const type = await queryOne('SELECT name FROM product_types WHERE id = ?',row.product_type_id);
  const full = qty >= row.remaining;
  const at = nowISO();

  // Imha adedi discards tablosuna yazilir; parti guncellemesiyle ayni islemde
  // olmasi gerekir, yoksa biri basarisiz olunca zayi raporu stokla tutmaz.
  await transaction(async (client) => {
    await execute(
      'INSERT INTO discards (store_id, batch_id, quantity, reason, discarded_at, discarded_by) VALUES (?,?,?,?,?,?)',
      [row.store_id, row.id, qty, reason || 'Belirtilmedi', at, req.user.id], client
    );
    if (full) {
      await execute(
        "UPDATE batches SET status = 'discarded', discarded_at = ?, discard_reason = ?, remaining = 0 WHERE id = ?",
        [at, reason || 'Belirtilmedi', row.id], client
      );
      await execute(
        "UPDATE transfer_approvals SET status = 'cancelled', decided_at = ?, decision_note = ? WHERE batch_id = ? AND status = 'pending'",
        [at, 'Ürün imha edildi', row.id], client
      );
    } else {
      await execute('UPDATE batches SET remaining = remaining - ? WHERE id = ?', [qty, row.id], client);
    }
  });

  await logActivity(req.user, 'IMHA', 'batch', row.id,
    full
      ? `${type.name} tamamen imha edildi (${qty} adet, ${reason || 'sebep belirtilmedi'})`
      : `${type.name} kısmi imha: ${qty} adet (${reason || 'sebep belirtilmedi'})`,
    row.store_id);

  res.json({
    ok: true,
    remaining: full ? 0 : row.remaining - qty,
    status: full ? 'discarded' : row.status,
  });
});

// Donuk depodaki ürüne stok ekle (adetli)
router.post('/:id/add-stock', async (req, res) => {
  const row = await queryOne('SELECT * FROM batches WHERE id = ?',Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req);
  if (row.status !== 'frozen') return res.status(400).json({ error: 'Yalnızca donuk depodaki ürüne stok eklenebilir' });
  const qty = Number(req.body.quantity);
  if (!Number.isInteger(qty) || qty < 1) return res.status(400).json({ error: 'Miktar en az 1 olmalıdır' });
  await execute('UPDATE batches SET quantity = quantity + ?, remaining = remaining + ? WHERE id = ?',qty, qty, row.id);
  const type = await queryOne('SELECT name FROM product_types WHERE id = ?',row.product_type_id);
  await logActivity(req.user, 'STOK_EKLE', 'batch', row.id, `${type.name} donuk stoka ${qty} adet eklendi`, row.store_id);
  res.json({ ok: true, quantity: row.quantity + qty, remaining: row.remaining + qty });
});

// Satış işaretleme
// Satis ve ikram ayni akisi paylasir: ikisi de stoktan duser ve ayni kurallara
// (food dolabinda olmak, SKT dolmamis olmak) tabidir. Fark kaydin turunde:
// ikram ciroya ve satis adetlerine girmez.
router.post('/:id/sell', async (req, res) => {
  const kind = req.body.kind === 'ikram' ? 'ikram' : 'sale';
  const isIkram = kind === 'ikram';
  const verb = isIkram ? 'ikram edilebilir' : 'satılabilir';

  // Satis ve ikram ayni uc noktada oldugu icin yetki middleware ile degil
  // gövdedeki kind'a gore burada kontrol edilir.
  if (isIkram && req.user.role !== 'super_admin') {
    const me = await queryOne('SELECT role, permissions FROM users WHERE id = ?', req.user.id);
    if (!permissionsOf(me).includes('ikram')) {
      return res.status(403).json({ error: 'İkram yetkiniz yok' });
    }
  }

  const row = await queryOne('SELECT * FROM batches WHERE id = ?',Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  requireStoreAccessForBatch(row.store_id, req);
  if (row.status !== 'food_cabinet') return res.status(400).json({ error: `Yalnızca food dolabındaki ürünler ${verb}` });
  if (row.skt_end && Date.now() > new Date(row.skt_end).getTime()) {
    // SKT dolan urun ikram da edilemez; gida guvenligi kurali ayni.
    return res.status(400).json({
      error: `Bu ürünün SKT süresi doldu, ${isIkram ? 'ikram edilemez' : 'satış yapılamaz'}. İmha edilmelidir.`,
    });
  }

  const qty = Number(req.body.quantity);
  if (!Number.isInteger(qty) || qty < 1) return res.status(400).json({ error: 'Miktar en az 1 olmalıdır' });
  if (qty > row.remaining) return res.status(400).json({ error: `Yeterli stok yok. Kalan: ${row.remaining}` });

  // Birim fiyat pasta cesidinden gelir; satirda anlik goruntusu saklanir ki
  // sonradan yapilan fiyat degisiklikleri gecmis ciroyu bozmasin. Ikramda da
  // yazilir: bedelsiz verilenin degeri raporlanabilsin.
  const type = await queryOne('SELECT name, unit_price FROM product_types WHERE id = ?',row.product_type_id);
  const unitPrice = type && type.unit_price !== null && type.unit_price !== undefined ? Number(type.unit_price) : null;

  const newRemaining = row.remaining - qty;
  const newStatus = newRemaining === 0 ? 'sold' : row.status;
  const soldAt = nowISO();

  const r = await execute(
    'INSERT INTO sales (store_id, batch_id, quantity, unit_price, kind, sold_at, sold_by) VALUES (?,?,?,?,?,?,?) RETURNING id'
  ,row.store_id, row.id, qty, unitPrice, kind, soldAt, req.user.id);

  await execute('UPDATE batches SET remaining = ?, status = ?, sold_at = ? WHERE id = ?',
    newRemaining, newStatus, newStatus === 'sold' ? soldAt : row.sold_at, row.id
  );

  const valueNote = unitPrice !== null ? ` (birim: ${unitPrice} TL, tutar: ${qty * unitPrice} TL)` : ' (fiyat tanımlı değil)';
  await logActivity(req.user, isIkram ? 'IKRAM' : 'SATIS', 'batch', row.id,
    isIkram
      ? `${type.name} ${qty} adet ikram edildi${valueNote}`
      : `${type.name} ${qty} adet satıldı${valueNote}`,
    row.store_id);
  res.status(201).json({
    id: Number(r.lastInsertRowid), remaining: newRemaining, status: newStatus, kind,
    unit_price: unitPrice, total: unitPrice !== null ? qty * unitPrice : null,
  });
});

// Yonetici duzeltmesi: yanlis girilen tarih/saat ve adetleri duzeltir.
// Durum gecisleri buradan yapilmaz; yalnizca mevcut kaydin verisi duzeltilir.
const TIMESTAMP_LABELS = {
  entered_frozen_at: 'Donuk depoya giriş',
  thawing_started_at: 'Çözülme başlangıcı',
  thawing_finish_at: 'Çözülme bitişi',
  food_cabinet_entered_at: 'Food dolabına giriş',
  skt_end: 'SKT bitiş',
};

router.put('/:id/adjust', requirePermission('adjust_batches'), async (req, res) => {
  const row = await queryOne('SELECT * FROM batches WHERE id = ?',Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'Ürün bulunamadı' });
  const body = req.body || {};

  let quantity = row.quantity;
  if (body.quantity !== undefined && body.quantity !== '' && body.quantity !== null) {
    quantity = Number(body.quantity);
    if (!Number.isInteger(quantity) || quantity < 1) {
      return res.status(400).json({ error: 'Toplam adet en az 1 olmalıdır' });
    }
  }
  let remaining = row.remaining;
  if (body.remaining !== undefined && body.remaining !== '' && body.remaining !== null) {
    remaining = Number(body.remaining);
    if (!Number.isInteger(remaining) || remaining < 0) {
      return res.status(400).json({ error: 'Kalan adet 0 veya daha büyük olmalıdır' });
    }
  }
  if (remaining > quantity) {
    return res.status(400).json({ error: `Kalan adet toplam adetten büyük olamaz (toplam: ${quantity})` });
  }

  const stamps = {};
  for (const key of Object.keys(TIMESTAMP_LABELS)) {
    if (body[key] === undefined) { stamps[key] = row[key]; continue; }
    if (body[key] === null || body[key] === '') { stamps[key] = null; continue; }
    const parsed = new Date(body[key]);
    if (Number.isNaN(parsed.getTime())) {
      return res.status(400).json({ error: `Geçersiz tarih: ${TIMESTAMP_LABELS[key]}` });
    }
    stamps[key] = parsed.toISOString();
  }
  if (!stamps.entered_frozen_at) {
    return res.status(400).json({ error: 'Donuk depoya giriş tarihi zorunludur' });
  }

  // Erken aktarimda food dolabina giris cozulme bitisinden once olabilir,
  // bu yuzden yalnizca kesin olan siralamalar dogrulanir.
  const ordered = [
    ['entered_frozen_at', 'thawing_started_at'],
    ['thawing_started_at', 'thawing_finish_at'],
    ['food_cabinet_entered_at', 'skt_end'],
  ];
  for (const [earlier, later] of ordered) {
    if (stamps[earlier] && stamps[later] && new Date(stamps[earlier]) > new Date(stamps[later])) {
      return res.status(400).json({
        error: `${TIMESTAMP_LABELS[earlier]}, ${TIMESTAMP_LABELS[later]} tarihinden sonra olamaz`,
      });
    }
  }

  const changes = [];
  if (quantity !== row.quantity) changes.push(`toplam adet ${row.quantity} -> ${quantity}`);
  if (remaining !== row.remaining) changes.push(`kalan adet ${row.remaining} -> ${remaining}`);
  for (const [key, label] of Object.entries(TIMESTAMP_LABELS)) {
    const before = row[key] ? new Date(row[key]).getTime() : null;
    const after = stamps[key] ? new Date(stamps[key]).getTime() : null;
    if (before !== after) {
      changes.push(`${label}: ${row[key] || 'yok'} -> ${stamps[key] || 'yok'}`);
    }
  }
  if (changes.length === 0) return res.json({ ok: true, changes: [] });

  await execute(`
    UPDATE batches SET quantity = ?, remaining = ?, entered_frozen_at = ?, thawing_started_at = ?,
      thawing_finish_at = ?, food_cabinet_entered_at = ?, skt_end = ? WHERE id = ?
  `,quantity, remaining, stamps.entered_frozen_at, stamps.thawing_started_at,
    stamps.thawing_finish_at, stamps.food_cabinet_entered_at, stamps.skt_end, row.id);

  const type = await queryOne('SELECT name FROM product_types WHERE id = ?',row.product_type_id);
  await logActivity(req.user, 'KAYIT_DUZELT', 'batch', row.id,
    `${type.name} kaydı düzeltildi — ${changes.join('; ')}`, row.store_id);

  res.json({ ok: true, changes });
});

module.exports = router;
