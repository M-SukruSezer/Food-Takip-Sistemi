const express = require('express');
const { db } = require('../db');
const { requireAuth, requireRole, hashPassword } = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

router.use(requireAuth);

// Kullanıcı listesi:
// - super_admin: tüm mağazalar
// - store_manager: yalnızca kendi mağazası
router.get('/', (req, res) => {
  let rows;
  if (req.user.role === 'super_admin') {
    rows = db.prepare(`
      SELECT u.id, u.username, u.full_name, u.role, u.active, u.store_id, u.created_at, s.name AS store_name
      FROM users u LEFT JOIN stores s ON s.id = u.store_id ORDER BY u.created_at DESC
    `).all();
  } else {
    if (req.user.role !== 'store_manager') return res.status(403).json({ error: 'Bu işlem için yetkiniz yok' });
    rows = db.prepare(`
      SELECT u.id, u.username, u.full_name, u.role, u.active, u.store_id, u.created_at, s.name AS store_name
      FROM users u LEFT JOIN stores s ON s.id = u.store_id WHERE u.store_id = ? ORDER BY u.created_at DESC
    `).all(req.user.store_id);
  }
  res.json(rows);
});

router.post('/', (req, res) => {
  const { username, password, full_name, role, store_id, active } = req.body || {};
  if (!username || !password || !full_name || !role) {
    return res.status(400).json({ error: 'Kullanıcı adı, şifre, ad soyad ve rol zorunludur' });
  }
  if (String(password).length < 6) return res.status(400).json({ error: 'Şifre en az 6 karakter olmalıdır' });

  let sid = store_id || null;
  if (req.user.role !== 'super_admin') {
    // mağaza yöneticisi yalnızca kendi mağazasına kullanıcı ekleyebilir
    sid = req.user.store_id;
    if (!['store_manager', 'staff'].includes(role)) {
      return res.status(400).json({ error: 'Mağaza yöneticisi yalnızca personel veya mağaza müdürü oluşturabilir' });
    }
  }
  if (req.user.role === 'super_admin' && role === 'super_admin') sid = null;

  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(String(username).trim());
  if (existing) return res.status(400).json({ error: 'Bu kullanıcı adı zaten kullanılıyor' });

  const r = db.prepare(
    'INSERT INTO users (store_id, username, password_hash, full_name, role, active) VALUES (?,?,?,?,?,?)'
  ).run(sid, String(username).trim(), hashPassword(String(password)), String(full_name).trim(), role, active === false ? 0 : 1);
  logActivity(req.user, 'KULLANICI_OLUSTUR', 'user', r.lastInsertRowid, `${full_name} (${username}) oluşturuldu`);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

router.put('/:id', (req, res) => {
  const existing = db.prepare('SELECT * FROM users WHERE id = ?').get(Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Kullanıcı bulunamadı' });

  const { full_name, role, active, store_id } = req.body || {};

  if (req.user.role === 'store_manager') {
    if (existing.store_id !== req.user.store_id) return res.status(403).json({ error: 'Bu kullanıcıya erişim yetkiniz yok' });
    if (existing.id === req.user.id) return res.status(400).json({ error: 'Kendi hesabınızı buradan düzenleyemezsiniz' });
    if (role && !['store_manager', 'staff'].includes(role)) return res.status(400).json({ error: 'Geçersiz rol' });
  }
  if (req.user.role === 'super_admin' && existing.id === req.user.id && (role && role !== 'super_admin')) {
    return res.status(400).json({ error: 'Kendi rolünüzü değiştiremezsiniz' });
  }
  if (existing.id === req.user.id && active === false) {
    return res.status(400).json({ error: 'Kendi hesabınızı pasife alamazsınız' });
  }

  const newRole = role || existing.role;
  let sid = existing.store_id;
  if (req.user.role === 'super_admin') {
    sid = store_id !== undefined ? store_id : existing.store_id;
    if (newRole === 'super_admin') sid = null;
  }

  db.prepare('UPDATE users SET full_name = ?, role = ?, active = ?, store_id = ? WHERE id = ?').run(
    (full_name || existing.full_name), newRole, active === undefined ? existing.active : (active ? 1 : 0), sid, existing.id
  );
  logActivity(req.user, 'KULLANICI_GUNCELLE', 'user', existing.id, `${existing.username} güncellendi`);
  res.json({ ok: true });
});

router.post('/:id/password', (req, res) => {
  const existing = db.prepare('SELECT * FROM users WHERE id = ?').get(Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Kullanıcı bulunamadı' });
  const { password } = req.body || {};
  if (!password || String(password).length < 6) return res.status(400).json({ error: 'Şifre en az 6 karakter olmalıdır' });
  if (req.user.role === 'store_manager' && existing.store_id !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu kullanıcıya erişim yetkiniz yok' });
  }
  db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(hashPassword(String(password)), existing.id);
  logActivity(req.user, 'SIFRE_SIFIRLA', 'user', existing.id, `${existing.username} şifresi sıfırlandı`);
  res.json({ ok: true });
});

router.delete('/:id', (req, res) => {
  const existing = db.prepare('SELECT * FROM users WHERE id = ?').get(Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Kullanıcı bulunamadı' });
  if (existing.id === req.user.id) return res.status(400).json({ error: 'Kendi hesabınızı silemezsiniz' });
  if (req.user.role === 'store_manager') {
    if (existing.store_id !== req.user.store_id) return res.status(403).json({ error: 'Bu kullanıcıya erişim yetkiniz yok' });
  }
  if (existing.role === 'super_admin') return res.status(400).json({ error: 'Ana yönetici hesabı silinemez' });
  db.prepare('DELETE FROM users WHERE id = ?').run(existing.id);
  logActivity(req.user, 'KULLANICI_SIL', 'user', existing.id, `${existing.username} silindi`);
  res.json({ ok: true });
});

module.exports = router;
