const express = require('express');
const { queryAll, queryOne, execute } = require('../db');
const {
  requireAuth, hashPassword,
  ALL_PERMISSIONS, DEFAULT_PERMISSIONS, PERMISSION_LABELS,
  permissionsOf, parsePermissions, serializePermissions,
  ROLES, ROLE_LABELS, MANAGER_ROLES, roleLevel, assignableRoles, isMultiStoreRole,
  storeFilter, resolveStoreScope,
} = require('../auth');

// Kullanicinin sorumlu oldugu magazalar (cok magazali roller icin).
async function storeIdsOf(userId) {
  const rows = await queryAll('SELECT store_id FROM user_stores WHERE user_id = ?', userId);
  return rows.map((r) => Number(r.store_id));
}

async function setStoreIds(userId, ids) {
  await execute('DELETE FROM user_stores WHERE user_id = ?', userId);
  for (const id of [...new Set(ids)]) {
    await execute('INSERT INTO user_stores (user_id, store_id) VALUES (?,?)', userId, id);
  }
}

/// Hedef kullanici, islemi yapanin yonetim alaninda mi?
/// Kural: yalnizca kendinden ASAGI kademedeki kullanicilar ve yalnizca
/// erisebildigi magazalardakiler.
function canManageUser(req, target) {
  if (roleLevel(target.role) <= roleLevel(req.user.role)) return false;
  if (req.storeIds === null) return true;
  // Magazasi olmayan bir kullaniciyi yalnizca Ana Yonetici yonetebilir.
  if (!target.store_id) return false;
  return req.storeIds.includes(Number(target.store_id));
}
const { logActivity } = require('../utils');

const router = express.Router();

router.use(requireAuth);

// Kullanıcı listesi:
// - super_admin: tüm mağazalar
// - store_manager: yalnızca kendi mağazası
router.get('/', async (req, res) => {
  if (!MANAGER_ROLES.includes(req.user.role)) {
    return res.status(403).json({ error: 'Bu işlem için yetkiniz yok' });
  }
  const scope = resolveStoreScope(req, res);
  if (!scope.ok) return undefined;

  // Yalnizca kendi kademesinin altindakiler ve erisilen magazalardakiler.
  const below = ROLES.slice(roleLevel(req.user.role) + 1);
  const f = storeFilter(scope, 'u.store_id');
  const rows = await queryAll(`
    SELECT u.id, u.username, u.full_name, u.role, u.active, u.store_id, u.permissions, u.created_at,
           s.name AS store_name
    FROM users u LEFT JOIN stores s ON s.id = u.store_id
    WHERE u.role IN (${below.map(() => '?').join(',')}) ${f.sql}
    ORDER BY u.created_at DESC
  `, ...below, ...f.params);
  // Yetkiler kolonda JSON metin durur; arayuze dizi olarak verilir ve Ana
  // Yoneticinin ornek yetkileri her zaman tam listedir.
  // Cok magazali rollerin atamalari ayri tabloda.
  const withStores = await Promise.all(rows.map(async (r) => ({
    ...r,
    permissions: permissionsOf(r),
    store_ids: isMultiStoreRole(r.role) ? await storeIdsOf(r.id) : [],
  })));
  res.json(withStores);
});

// Arayuz onay kutularini bu listeden uretir, kod tekrarlanmaz.
router.get('/permissions', async (req, res) => {
  res.json(ALL_PERMISSIONS.map((key) => ({ key, label: PERMISSION_LABELS[key] })));
});

// Islemi yapanin tanimlayabilecegi roller: kendinden asagi kademedekiler.
router.get('/roles', async (req, res) => {
  res.json(assignableRoles(req.user.role).map((key) => ({
    key,
    label: ROLE_LABELS[key],
    multi_store: isMultiStoreRole(key),
  })));
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

  // Yalnizca kendinden asagi kademedeki roller tanimlanabilir.
  const allowedRoles = assignableRoles(req.user.role);
  if (!allowedRoles.includes(role)) {
    return res.status(403).json({
      error: `Bu rolü tanımlayamazsınız. Tanımlayabildikleriniz: ${allowedRoles.map((r) => ROLE_LABELS[r]).join(', ')}`,
    });
  }

  let sid = store_id ? Number(store_id) : null;
  if (isMultiStoreRole(role)) {
    // Magaza atamasi user_stores'tan gelir; tekil alan bos kalir.
    sid = null;
  } else if (req.storeIds !== null) {
    // Tek magazali rolde: yalnizca erisebildigi magazalara kullanici eklenir.
    if (req.storeIds.length === 0) return res.status(403).json({ error: 'Size mağaza atanmamış' });
    if (sid === null) sid = req.storeIds.length === 1 ? req.storeIds[0] : null;
    if (sid === null) return res.status(400).json({ error: 'Mağaza seçmelisiniz' });
    if (!req.storeIds.includes(sid)) {
      return res.status(403).json({ error: 'Bu mağazaya kullanıcı ekleyemezsiniz' });
    }
  }

  const existing = await queryOne('SELECT id FROM users WHERE username = ?',String(username).trim());
  if (existing) return res.status(400).json({ error: 'Bu kullanıcı adı zaten kullanılıyor' });

  // Yetki listesi verilmezse varsayilan (zayi + ikram) uygulanir: yetki
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
  const newId = Number(r.lastInsertRowid);
  // Cok magazali rolde sorumluluk listesi ayri tabloya yazilir.
  if (isMultiStoreRole(role)) {
    const wanted = Array.isArray(req.body.store_ids) ? req.body.store_ids.map(Number) : [];
    const invalid = req.storeIds === null ? [] : wanted.filter((id) => !req.storeIds.includes(id));
    if (invalid.length > 0) {
      return res.status(403).json({ error: 'Erişiminiz olmayan mağaza atayamazsınız' });
    }
    await setStoreIds(newId, wanted);
  }
  await logActivity(req.user, 'KULLANICI_OLUSTUR', 'user', newId,
    `${full_name} (${username}) oluşturuldu — ${ROLE_LABELS[role] || role}`);
  res.status(201).json({ id: newId });
});

router.put('/:id', async (req, res) => {
  const existing = await queryOne('SELECT * FROM users WHERE id = ?',Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Kullanıcı bulunamadı' });

  const { full_name, role, active, store_id } = req.body || {};

  const isSelf = existing.id === req.user.id;
  if (!isSelf && !canManageUser(req, existing)) {
    return res.status(403).json({ error: 'Bu kullanıcıya erişim yetkiniz yok' });
  }
  if (isSelf && req.user.role !== 'super_admin') {
    return res.status(400).json({ error: 'Kendi hesabınızı buradan düzenleyemezsiniz' });
  }
  if (isSelf && role && role !== existing.role) {
    return res.status(400).json({ error: 'Kendi rolünüzü değiştiremezsiniz' });
  }
  if (isSelf && active === false) {
    return res.status(400).json({ error: 'Kendi hesabınızı pasife alamazsınız' });
  }
  // Rol degisiyorsa yeni rol de kendi kademesinin altinda olmali.
  if (role && role !== existing.role && !assignableRoles(req.user.role).includes(role)) {
    return res.status(403).json({ error: 'Bu rolü atayamazsınız' });
  }

  const newRole = role || existing.role;
  let sid = existing.store_id;
  if (isMultiStoreRole(newRole)) {
    sid = null;
  } else if (store_id !== undefined) {
    const wanted = store_id === null ? null : Number(store_id);
    if (wanted !== null && req.storeIds !== null && !req.storeIds.includes(wanted)) {
      return res.status(403).json({ error: 'Bu mağazaya atama yapamazsınız' });
    }
    sid = wanted;
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
  if (isMultiStoreRole(newRole) && req.body.store_ids !== undefined) {
    const wanted = Array.isArray(req.body.store_ids) ? req.body.store_ids.map(Number) : [];
    const invalid = req.storeIds === null ? [] : wanted.filter((id) => !req.storeIds.includes(id));
    if (invalid.length > 0) {
      return res.status(403).json({ error: 'Erişiminiz olmayan mağaza atayamazsınız' });
    }
    await setStoreIds(existing.id, wanted);
  } else if (!isMultiStoreRole(newRole)) {
    // Rol tek magazaliya dondugunde eski coklu atamalar temizlenir.
    await execute('DELETE FROM user_stores WHERE user_id = ?', existing.id);
  }

  await logActivity(req.user, 'KULLANICI_GUNCELLE', 'user', existing.id,
    `${existing.username} güncellendi${permissionNote}`);
  res.json({ ok: true });
});

router.post('/:id/password', async (req, res) => {
  const existing = await queryOne('SELECT * FROM users WHERE id = ?',Number(req.params.id));
  if (!existing) return res.status(404).json({ error: 'Kullanıcı bulunamadı' });
  const { password } = req.body || {};
  if (!password || String(password).length < 6) return res.status(400).json({ error: 'Şifre en az 6 karakter olmalıdır' });
  if (existing.id !== req.user.id && !canManageUser(req, existing)) {
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
  if (!canManageUser(req, existing)) {
    return res.status(403).json({ error: 'Bu kullanıcıya erişim yetkiniz yok' });
  }
  if (existing.role === 'super_admin') return res.status(400).json({ error: 'Ana yönetici hesabı silinemez' });
  await execute('DELETE FROM users WHERE id = ?',existing.id);
  await logActivity(req.user, 'KULLANICI_SIL', 'user', existing.id, `${existing.username} silindi`);
  res.json({ ok: true });
});

module.exports = router;
