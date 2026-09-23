const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { queryOne } = require('./db');

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

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Giriş yapmanız gerekiyor' });
  try {
    req.user = jwt.verify(token, SIGNING_SECRET);
    next();
  } catch (e) {
    return res.status(401).json({ error: 'Oturum süresi doldu, lütfen tekrar giriş yapın' });
  }
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Bu işlem için yetkiniz yok' });
    }
    next();
  };
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

module.exports = {
  sign, hashPassword, verifyPassword, requireAuth, requireRole, storeScope,
  ALL_PERMISSIONS, DEFAULT_PERMISSIONS, PERMISSION_LABELS, PERMISSION_ERRORS,
  parsePermissions, permissionsOf, serializePermissions, requirePermission,
};
