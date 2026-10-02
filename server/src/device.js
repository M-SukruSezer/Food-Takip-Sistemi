// Hesap-telefon eslestirmesi.
//
// Personel hesabini ilk actigi telefona eslesir. Ayni hesap BASKA bir
// telefondan acilmaya calisilinca hesap bloke edilir, yoneticilere bildirim
// gider; blokeyi yalnizca yonetici kaldirir. Boylece kimse bir baskasinin
// telefonunda onun hesabini acip onun adina giris-cikis yapamaz.
//
// Telefon kimligi istemciden X-Device-Id basligiyla gelir (Android'de
// ANDROID_ID). Tarayici kimlik gondermez: web girisi eslestirmeyi
// etkilemez, ancak eslesmis bir hesap giris-cikisi yalnizca telefonundan
// yapabilir (requireBoundDevice).

const { queryOne, queryAll, execute, nowISO } = require('./db');

/// Eslestirme disindaki roller: Ana Yonetici (blokesini kaldiracak ust kademe
/// yok) ve magaza hesabi (kisi degil, magazadaki ortak cihaz).
const DEVICE_EXEMPT_ROLES = ['super_admin', 'store'];

const BLOCKED_MESSAGE = 'Hesabınız başka bir telefondan giriş denemesi nedeniyle bloke edildi. '
  + 'Yöneticinizin blokeyi kaldırması gerekiyor.';

function isExempt(role) {
  return DEVICE_EXEMPT_ROLES.includes(role);
}

/// Istekteki telefon kimligi ve adi (yoksa null).
function deviceOf(req) {
  const raw = (h) => {
    const v = req.headers[h];
    const s = (Array.isArray(v) ? v[0] : v || '').trim();
    return s ? s.slice(0, 200) : null;
  };
  return { id: raw('x-device-id'), name: raw('x-device-name') };
}

/// Bloke olan personelin yoneticileri: kendisinden ust kademede, magazasini
/// yoneten aktif kullanicilar.
async function managersOf(user) {
  const { MANAGER_ROLES, roleLevel } = require('./auth');
  const ph = MANAGER_ROLES.map(() => '?').join(',');
  const rows = await queryAll(`
    SELECT u.id, u.role FROM users u
    WHERE u.active = 1 AND u.role IN (${ph}) AND u.id <> ?
      AND (u.role = 'super_admin' OR u.store_id = ?
           OR EXISTS (SELECT 1 FROM user_stores us WHERE us.user_id = u.id AND us.store_id = ?))`,
  ...MANAGER_ROLES, user.id, user.store_id, user.store_id);
  return rows
    .filter((r) => roleLevel(r.role) < roleLevel(user.role))
    .map((r) => Number(r.id));
}

/// Hesabi bloke eder, kayda yazar ve yoneticilere bildirir.
async function blockUser(user, device) {
  const now = nowISO();
  await execute(`
    UPDATE users SET device_blocked = 1, device_blocked_at = ?,
      blocked_device_id = ?, blocked_device_name = ?
    WHERE id = ?`, now, device.id, device.name, user.id);
  const { logActivity } = require('./utils');
  const cihaz = device.name ? ` (${device.name})` : '';
  await logActivity(user, 'CIHAZ_BLOKE', 'user', user.id,
    `${user.full_name} hesabı başka bir telefondan${cihaz} açılmaya çalışıldı; hesap bloke edildi`,
    user.store_id || null);
  const notify = require('./pdks/notify');
  for (const managerId of await managersOf(user)) {
    await notify.publish({
      userId: managerId,
      kind: notify.KIND.deviceBlocked,
      title: 'Hesap bloke edildi',
      body: `${user.full_name} hesabı kayıtlı telefonu dışında bir cihazdan${cihaz} `
        + 'açılmaya çalışıldı. Blokeyi Kullanıcılar ekranından kaldırabilirsiniz.',
      data: { user_id: user.id, screen: '/users' },
    });
  }
}

/// Kullanici satiri + istekteki telefon icin karar.
///   { ok: true }                         devam
///   { ok: false, status, error, code }   reddet
/// Ilk kez telefondan gelen hesap burada telefona eslestirilir.
async function checkDevice(user, device) {
  if (!user || isExempt(user.role)) return { ok: true };
  if (Number(user.device_blocked) === 1) {
    return { ok: false, status: 403, error: BLOCKED_MESSAGE, code: 'DEVICE_BLOCKED' };
  }
  if (!device.id) return { ok: true };
  if (user.device_id === device.id) return { ok: true };

  if (user.device_id) {
    await blockUser(user, device);
    return { ok: false, status: 403, error: BLOCKED_MESSAGE, code: 'DEVICE_BLOCKED' };
  }

  // Ilk eslestirme. Telefon baska bir hesaba aitse acilmaz: bir telefonda
  // tek personel hesabi.
  const owner = await queryOne(
    'SELECT id FROM users WHERE device_id = ? AND id <> ?', device.id, user.id);
  if (owner) {
    return {
      ok: false,
      status: 403,
      error: 'Bu telefon başka bir personelin hesabına kayıtlı. '
        + 'Kendi telefonunuzdan giriş yapın ya da yöneticinizden cihaz sıfırlaması isteyin.',
      code: 'DEVICE_TAKEN',
    };
  }
  await execute(`
    UPDATE users SET device_id = ?, device_name = ?, device_bound_at = ?
    WHERE id = ? AND device_id IS NULL`, device.id, device.name, nowISO(), user.id);
  user.device_id = device.id;
  return { ok: true };
}

/// requireAuth icin: jetondaki kullanicinin cihaz durumu. Satir yoksa
/// (silinmis kullanici) burada karar verilmez.
async function checkRequestDevice(req) {
  if (isExempt(req.user.role)) return { ok: true };
  const user = await queryOne(`
    SELECT id, username, full_name, role, store_id, device_id, device_blocked
    FROM users WHERE id = ?`, req.user.id);
  if (!user) return { ok: true };
  req.deviceBound = !!user.device_id;
  return checkDevice(user, deviceOf(req));
}

/// Giris-cikis kaydi: eslesmis hesap yalnizca kendi telefonundan okutur
/// (web tarayicisindan ya da baska telefondan olmaz).
async function requireBoundDevice(req, res, next) {
  if (isExempt(req.user.role)) return next();
  const row = await queryOne('SELECT device_id FROM users WHERE id = ?', req.user.id);
  if (!row || !row.device_id) return next();
  if (deviceOf(req).id !== row.device_id) {
    return res.status(403).json({
      error: 'Giriş-çıkış yalnızca hesabınıza kayıtlı telefondan yapılabilir',
      code: 'DEVICE_REQUIRED',
    });
  }
  return next();
}

module.exports = {
  DEVICE_EXEMPT_ROLES, BLOCKED_MESSAGE, isExempt, deviceOf, checkDevice,
  checkRequestDevice, requireBoundDevice, managersOf,
};
