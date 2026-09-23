const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const {
  requireAuth, hashPassword,
  ALL_PERMISSIONS, DEFAULT_PERMISSIONS, PERMISSION_LABELS,
  permissionsOf, parsePermissions, serializePermissions,
} = require('../auth');
const { logActivity } = require('../utils');

const router = express.Router();

router.use(requireAuth);

// Kullanıcı listesi:
// - super_admin: tüm mağazalar
// - store_manager: yalnızca kendi mağazası
router.get('/', async (req, res) => {
  let rows;
  if (req.user.role === 'super_admin') {
    rows = await queryAll(`
      SELECT u.id, u.username, u.full_name, u.role, u.active, u.store_id, u.permissions, u.created_at,
             s.name AS store_name
      FROM users u LEFT JOIN stores s ON s.id = u.store_id ORDER BY u.created_at DESC
    `,);
  } else {
    if (req.user.role !== 'store_manager') return res.status(403).json({ error: 'Bu işlem için yetkiniz yok' });
    rows = await queryAll(`
      SELECT u.id, u.username, u.full_name, u.role, u.active, u.store_id, u.permissions, u.created_at,
             s.name AS store_name
      FROM users u LEFT JOIN stores s ON s.id = u.store_id WHERE u.store_id = ? ORDER BY u.created_at DESC
    `,req.user.store_id);
  }
  // Yetkiler kolonda JSON metin durur; arayuze dizi olarak verilir ve Ana
  // Yoneticinin ornek yetkileri her zaman tam listedir.
  res.json(rows.map((r) => ({ ...r, permissions: permissionsOf(r) })));
});

// Arayuz onay kutularini bu listeden uretir, kod tekrarlanmaz.
router.get('/permissions', async (req, res) => {
  res.json(ALL_PERMISSIONS.map((key) => ({ key, label: PERMISSION_LABELS[key] })));
});

// Bir kullanicinin verebilecegi yetkiler: Ana Yonetici hepsini, digerleri
// yalnizca kendi sahip olduklarini devredebilir (yetki yukseltmesi olmasin).
async function grantableBy(user) {
  if (user.role === 'super_admin') return [...ALL_PERMISSIONS];
  const me = await queryOne('SELECT role, permissions FROM users WHERE id = ?', user.id);
  return permissionsOf(me);
}

router.post('/', async (req, res) => {
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

  const existing = await queryOne('SELECT id FROM users WHERE username = ?',String(username).trim());
  if (existing) return res.status(400).json({ error: 'Bu kullanıcı adı zaten kullanılıyor' });

  // Yetki listesi verilmezse varsayilan (imha + ikram) uygulanir: yetki
  // sistemi oncesi davranis buydu.
  const grantable = await grantableBy(req.user);
  const wanted = req.body.permissions === undefined
    ? DEFAULT_PERMISSIONS
    : parsePermissions(req.body.permissions);
  const forbidden = wanted.filter((perm) => !grantable.includes(perm));
  if (forbidden.length > 0) {
    return res.status(403).json({
      error: `Sahip olmadığınız yetkiyi veremezsiniz: ${forbidden.map((p) => PERMISSION_LABELS[p]).join(', ')}`,
    });
  }
  // Ana Yonetici hesabinda kolon bos kalir; yetkileri rolunden gelir.
  const permissions = role === 'super_admin' ? null : serializePermissions(wanted);

  const r = await execute(
    'INSERT INTO users (store_id, username, password_hash, full_name, role, active, permissions) VALUES (?,?,?,?,?,?,?) RETURNING id'
  ,sid, String(username).trim(), hashPassword(String(password)), String(full_name).trim(), role, active === false ? 0 : 1, permissions);
  await logActivity(req.user, 'KULLANICI_OLUSTUR', 'user', r.lastInsertRowid, `${full_name} (${username}) oluşturuldu`);
  res.status(201).json({ id: Number(r.lastInsertRowid) });
});

router.put('/:id', async (req, res) => {
  const existing = await queryOne('SELECT * FROM users WHERE id = ?',Number(req.params.id));
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

  let permissions = existing.permissions;
  if (req.body.permissions !== undefined) {
    const grantable = await grantableBy(req.user);
    const wanted = parsePermissions(req.body.permissions);
    const current = permissionsOf(existing);
    // Hem verilen hem geri alinan yetki, islemi yapanin yetki alaninda olmali.
    const touched = [...new Set([...wanted, ...current])]
      .filter((perm) => wanted.includes(perm) !== current.includes(perm));
    const forbidden = touched.filter((perm) => !grantable.includes(perm));
    if (forbidden.length > 0) {
      return res.status(403).json({
        error: `Sahip olmadığınız yetkiyi değiştiremezsiniz: ${forbidden.map((p) => PERMISSION_LABELS[p]).join(', ')}`,
      });
    }
    permissions = serializePermissions(wanted);
  }
  if (newRole === 'super_admin') permissions = null;

  await execute('UPDATE users SET full_name = ?, role = ?, active = ?, store_id = ?, permissions = ? WHERE id = ?',
    (full_name || existing.full_name), newRole, active === undefined ? existing.active : (active ? 1 : 0), sid,
    permissions, existing.id
  );
  const permissionNote = req.body.permissions === undefined
    ? ''
    : ` (yetkiler: ${permissionsOf({ role: newRole, permissions }).map((p) => PERMISSION_LABELS[p]).join(', ') || 'yok'})`;
  await logActivity(req.user, 'KULLANICI_GUNCELLE', 'user', existing.id,
    `${existing.username} güncellendi${permissionNote}`);
  res.json({ ok: true });
});

router.post('/:id/password', async (req, res) => {
  const existing = await queryOne('SELECT * FROM users WHERE id = ?',Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Kullanıcı bulunamadı' });
  const { password } = req.body || {};
  if (!password || String(password).length < 6) return res.status(400).json({ error: 'Şifre en az 6 karakter olmalıdır' });
  if (req.user.role === 'store_manager' && existing.store_id !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu kullanıcıya erişim yetkiniz yok' });
  }
  await execute('UPDATE users SET password_hash = ? WHERE id = ?',hashPassword(String(password)), existing.id);
  await logActivity(req.user, 'SIFRE_SIFIRLA', 'user', existing.id, `${existing.username} şifresi sıfırlandı`);
  res.json({ ok: true });
});

router.delete('/:id', async (req, res) => {
  const existing = await queryOne('SELECT * FROM users WHERE id = ?',Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Kullanıcı bulunamadı' });
  if (existing.id === req.user.id) return res.status(400).json({ error: 'Kendi hesabınızı silemezsiniz' });
  if (req.user.role === 'store_manager') {
    if (existing.store_id !== req.user.store_id) return res.status(403).json({ error: 'Bu kullanıcıya erişim yetkiniz yok' });
  }
  if (existing.role === 'super_admin') return res.status(400).json({ error: 'Ana yönetici hesabı silinemez' });
  await execute('DELETE FROM users WHERE id = ?',existing.id);
  await logActivity(req.user, 'KULLANICI_SIL', 'user', existing.id, `${existing.username} silindi`);
  res.json({ ok: true });
});

module.exports = router;
