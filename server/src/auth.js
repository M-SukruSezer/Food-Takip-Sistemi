const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

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

module.exports = { sign, hashPassword, verifyPassword, requireAuth, requireRole, storeScope };
