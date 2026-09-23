const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const { sign, verifyPassword, requireAuth, permissionsOf } = require('../auth');
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
      avatar: user.avatar || null,
      // Arayuz yetkisiz dugmeleri bastan gizlesin; son soz sunucuda.
      permissions: permissionsOf(user),
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
    avatar: user.avatar || null,
    permissions: permissionsOf(user),
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

// Profil fotosu. Istemci gorseli 256px'e kucultup JPEG veri URL'si olarak
// gonderir; burada yalnizca bicim ve boyut dogrulanir. Sunucusuz ortamda
// dosya sistemi kalici olmadigi icin gorsel satirda saklanir.
const AVATAR_MAX_CHARS = 400000; // ~300 KB ikili veri
const AVATAR_PATTERN = /^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/;

router.post('/avatar', requireAuth, async (req, res) => {
  const { avatar } = req.body || {};

  if (avatar === null || avatar === '') {
    await execute('UPDATE users SET avatar = NULL WHERE id = ?', req.user.id);
    await logActivity(req.user, 'PROFIL_FOTO', 'user', req.user.id, 'Profil fotoğrafı kaldırıldı');
    return res.json({ ok: true, avatar: null });
  }

  if (typeof avatar !== 'string' || !AVATAR_PATTERN.test(avatar)) {
    return res.status(400).json({ error: 'Geçersiz görsel biçimi. PNG, JPEG veya WEBP olmalıdır.' });
  }
  if (avatar.length > AVATAR_MAX_CHARS) {
    return res.status(400).json({ error: 'Görsel çok büyük. Lütfen daha küçük bir fotoğraf seçin.' });
  }

  await execute('UPDATE users SET avatar = ? WHERE id = ?', avatar, req.user.id);
  await logActivity(req.user, 'PROFIL_FOTO', 'user', req.user.id, 'Profil fotoğrafı güncellendi');
  res.json({ ok: true, avatar });
});

module.exports = router;
