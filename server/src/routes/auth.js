const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { sign, verifyPassword, requireAuth } = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

router.post('/login', async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) {
    return res.status(400).json({ error: 'Kullanıcı adı ve şifre zorunludur' });
  }
  const user = await queryOne('SELECT * FROM users WHERE username = ?',String(username).trim());
  if (!user || !verifyPassword(String(password), user.password_hash)) {
    return res.status(401).json({ error: 'Kullanıcı adı veya şifre hatalı' });
  }
  if (!user.active) {
    return res.status(403).json({ error: 'Hesabınız pasif durumda' });
  }
  const store = user.store_id
    ? await queryOne('SELECT name FROM stores WHERE id = ?',user.store_id)
    : null;
  if (user.store_id && !store) {
    return res.status(403).json({ error: 'Mağazanız bulunamadı' });
  }
  await logActivity(user, 'GIRIS', 'auth', user.id, 'Sisteme giriş yapıldı');
  const token = sign(user);
  res.json({
    token,
    user: {
      id: user.id,
      username: user.username,
      full_name: user.full_name,
      role: user.role,
      store_id: user.store_id,
      store_name: store ? store.name : null,
    },
  });
});

router.get('/me', requireAuth, async (req, res) => {
  const user = await queryOne('SELECT * FROM users WHERE id = ?',req.user.id);
  if (!user) return res.status(404).json({ error: 'Kullanıcı bulunamadı' });
  const store = user.store_id ? await queryOne('SELECT name FROM stores WHERE id = ?',user.store_id) : null;
  res.json({
    id: user.id,
    username: user.username,
    full_name: user.full_name,
    role: user.role,
    store_id: user.store_id,
    store_name: store ? store.name : null,
  });
});

router.post('/password', requireAuth, async (req, res) => {
  const { current, next: newPassword } = req.body || {};
  if (!current || !newPassword) {
    return res.status(400).json({ error: 'Mevcut ve yeni şifre zorunludur' });
  }
  if (String(newPassword).length < 6) {
    return res.status(400).json({ error: 'Yeni şifre en az 6 karakter olmalıdır' });
  }
  const user = await queryOne('SELECT * FROM users WHERE id = ?',req.user.id);
  if (!verifyPassword(String(current), user.password_hash)) {
    return res.status(400).json({ error: 'Mevcut şifre hatalı' });
  }
  const { hashPassword } = require('../auth');
  await execute('UPDATE users SET password_hash = ? WHERE id = ?',hashPassword(String(newPassword)), req.user.id);
  await logActivity(req.user, 'SIFRE_DEGISTIR', 'user', req.user.id, 'Kendi şifresini değiştirdi');
  res.json({ ok: true });
});

module.exports = router;
