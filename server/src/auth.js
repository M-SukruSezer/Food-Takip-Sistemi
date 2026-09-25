const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { queryOne, queryAll } = require('./db');

const JWT_SECRET = process.env.JWT_SECRET;

if (!JWT_SECRET && process.env.NODE_ENV === 'production') {
  throw new Error('JWT_SECRET production ortamında zorunludur');
}

const SIGNING_SECRET = JWT_SECRET || 'development-only-secret';

function sign(user) {
  return jwt.sign(
    { id: user.id, username: user.username, role: user.role, store_id: user.store_id, full_name: user.full_name },
    SIGNING_SECRET,
    { expiresIn: '12h' }
  );
}

function hashPassword(plain) {
  return bcrypt.hashSync(plain, 10);
}

function verifyPassword(plain, hash) {
  return bcrypt.compareSync(plain, hash);
}

async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Giriş yapmanız gerekiyor' });
  try {
    req.user = jwt.verify(token, SIGNING_SECRET);
  } catch (e) {
    return res.status(401).json({ error: 'Oturum süresi doldu, lütfen tekrar giriş yapın' });
  }
  // Erisilebilir magazalar istek basina bir kez cozulur; boylece rotalar
  // senkron kalir. Yalnizca cok magazali roller icin sorgu atilir.
  req.storeIds = await accessibleStoreIds(req.user);
  next();
}

/// Istek icin magaza erisim kontrolu. req.storeIds null ise tum magazalar.
function allowsStore(req, storeId) {
  if (req.storeIds === null) return true;
  return req.storeIds.includes(Number(storeId));
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Bu işlem için yetkiniz yok' });
    }
    next();
  };
}

// Rol kademeleri. Sira onemli: kucuk indis daha ust kademe. Bir kullanici
// yalnizca kendinden ASAGI kademedeki rolleri tanimlayabilir.
const ROLES = [
  'super_admin',
  'operations_manager',
  'regional_manager',
  'store_manager',
  'shift_supervisor',
  'barista',
];

const ROLE_LABELS = {
  super_admin: 'Ana Yönetici',
  operations_manager: 'Operations Manager',
  regional_manager: 'Regional Manager',
  store_manager: 'Store Manager',
  shift_supervisor: 'Shift Supervisor',
  barista: 'Barista',
};

/// Birden fazla magazadan sorumlu olabilen roller; magaza atamasi
/// user_stores tablosundan gelir.
const MULTI_STORE_ROLES = ['operations_manager', 'regional_manager'];

/// Kullanici yonetimi yapabilen roller (kendi altindakileri tanimlar).
const MANAGER_ROLES = ['super_admin', 'operations_manager', 'regional_manager', 'store_manager'];

function roleLevel(role) {
  const i = ROLES.indexOf(role);
  return i < 0 ? ROLES.length : i;
}

/// [actor] rolunun tanimlayabilecegi roller: kendinden asagidakiler.
function assignableRoles(actorRole) {
  return ROLES.slice(roleLevel(actorRole) + 1);
}

function isMultiStoreRole(role) {
  return MULTI_STORE_ROLES.includes(role);
}

// Ana Yoneticinin mağaza müdürlerine ve personele devredebildiği yetkiler.
// Rol sabit kalır; bu liste rolün üstüne eklenen izinlerdir.
const ALL_PERMISSIONS = ['manage_product_types', 'adjust_batches', 'discard', 'ikram'];

// Yeni kullanıcı imha ve ikram yapabilir: yetki sistemi gelmeden önceki
// davranış buydu, varsayılanı değiştirmek mevcut akışı kırardı.
const DEFAULT_PERMISSIONS = ['discard', 'ikram'];

const PERMISSION_LABELS = {
  manage_product_types: 'Pasta çeşidi yönetimi',
  adjust_batches: 'Parti düzeltme (tarih/adet)',
  discard: 'İmha',
  ikram: 'İkram',
};

const PERMISSION_ERRORS = {
  manage_product_types: 'Pasta çeşidi yönetimi yetkiniz yok',
  adjust_batches: 'Parti düzeltme yetkiniz yok',
  discard: 'İmha yetkiniz yok',
  ikram: 'İkram yetkiniz yok',
};

// Kolonda JSON dizi durur. Bozuk ya da bos deger yetkisizlik sayilir;
// bilinmeyen anahtarlar atilir ki eski kayitlar yeni yetki uydurmasin.
function parsePermissions(raw) {
  if (Array.isArray(raw)) return raw.filter((p) => ALL_PERMISSIONS.includes(p));
  if (typeof raw !== 'string' || !raw.trim()) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((p) => ALL_PERMISSIONS.includes(p)) : [];
  } catch (e) {
    return [];
  }
}

// Ana Yönetici her yetkiye sahiptir; kolonuna bakılmaz.
function permissionsOf(userRow) {
  if (!userRow) return [];
  if (userRow.role === 'super_admin') return [...ALL_PERMISSIONS];
  return parsePermissions(userRow.permissions);
}

function serializePermissions(list) {
  const clean = (Array.isArray(list) ? list : []).filter((p) => ALL_PERMISSIONS.includes(p));
  return JSON.stringify([...new Set(clean)]);
}

// Yetki token'dan degil veritabanindan okunur: token 12 saat gecerli oldugu
// icin iptal edilen bir yetki aksi halde saatlerce gecerli kalirdi.
function requirePermission(permission) {
  return async (req, res, next) => {
    if (req.user.role === 'super_admin') return next();
    const row = await queryOne('SELECT role, permissions FROM users WHERE id = ?', req.user.id);
    // Kullanici silinmisse permissionsOf bos dizi doner, kosul yine takilir.
    if (!permissionsOf(row).includes(permission)) {
      return res.status(403).json({ error: PERMISSION_ERRORS[permission] || 'Bu işlem için yetkiniz yok' });
    }
    next();
  };
}

// Mağaza bazlı erişim kısıtı:
// - super_admin: tüm mağazalara erişir (storeId istek parametresinden gelir)
// - diğer roller: yalnızca kendi mağazalarına erişir
function storeScope(req, res, next) {
  if (req.user.role === 'super_admin') {
    req.storeId = req.params.storeId ? Number(req.params.storeId) : null;
    return next();
  }
  if (!req.user.store_id) {
    return res.status(403).json({ error: 'Size mağaza atanmamış' });
  }
  req.storeId = req.user.store_id;
  if (req.params.storeId && Number(req.params.storeId) !== req.user.store_id) {
    return res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
  }
  next();
}

/// Kullanicinin erisebildigi magaza kimlikleri.
///   super_admin            -> null (tum magazalar)
///   operations/regional    -> user_stores atamalari
///   diger roller           -> kendi magazasi
/// Bos dizi donerse kullaniciya hic magaza atanmamistir.
async function accessibleStoreIds(user) {
  if (user.role === 'super_admin') return null;
  if (isMultiStoreRole(user.role)) {
    const rows = await queryAll('SELECT store_id FROM user_stores WHERE user_id = ?', user.id);
    return rows.map((r) => Number(r.store_id));
  }
  return user.store_id ? [Number(user.store_id)] : [];
}

/// Rota basinda magaza kapsamini cozer.
///   storeId  -> tek magazaya daraltilmissa o magaza, degilse null
///   storeIds -> null ise tum magazalar, dizi ise izin verilen magazalar
/// Yetkisiz istek icin yanit yazilir ve ok:false doner.
function resolveStoreScope(req, res) {
  const requested = req.query.storeId ? Number(req.query.storeId) : null;
  const ids = req.storeIds;

  if (ids === null) return { ok: true, storeId: requested, storeIds: null };
  if (ids.length === 0) {
    res.status(403).json({ error: 'Size mağaza atanmamış' });
    return { ok: false };
  }
  if (requested !== null) {
    if (!ids.includes(requested)) {
      res.status(403).json({ error: 'Bu mağazaya erişim yetkiniz yok' });
      return { ok: false };
    }
    return { ok: true, storeId: requested, storeIds: [requested] };
  }
  // Tek magazasi varsa dogrudan daraltilir; birden fazlaysa hepsi kapsama girer.
  return { ok: true, storeId: ids.length === 1 ? ids[0] : null, storeIds: ids };
}

/// Kapsami SQL parcasina cevirir. Cok magazali rollerde tek esitlik yetmiyor,
/// IN (...) gerekiyor.
///   scope.storeId  dolu  -> tek magaza
///   scope.storeIds null  -> filtre yok (tum magazalar)
///   aksi halde           -> IN (...)
function storeFilter(scope, column = 'store_id') {
  if (scope.storeId != null) return { sql: ` AND ${column} = ?`, params: [scope.storeId] };
  if (scope.storeIds === null) return { sql: '', params: [] };
  if (scope.storeIds.length === 0) return { sql: ' AND 1 = 0', params: [] };
  return {
    sql: ` AND ${column} IN (${scope.storeIds.map(() => '?').join(',')})`,
    params: [...scope.storeIds],
  };
}

module.exports = {
  sign, hashPassword, verifyPassword, requireAuth, requireRole, storeScope,
  ROLES, ROLE_LABELS, MANAGER_ROLES, roleLevel, assignableRoles, isMultiStoreRole,
  accessibleStoreIds, allowsStore, resolveStoreScope, storeFilter,
  ALL_PERMISSIONS, DEFAULT_PERMISSIONS, PERMISSION_LABELS, PERMISSION_ERRORS,
  parsePermissions, permissionsOf, serializePermissions, requirePermission,
};
