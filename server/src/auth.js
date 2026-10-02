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
  // Hesap-telefon eslestirmesi: bloke hesap hicbir istek yapamaz; hesap
  // kayitli telefonu disinda bir telefondan kullanilirsa bloke edilir.
  const cihaz = await require('./device').checkRequestDevice(req);
  if (!cihaz.ok) return res.status(cihaz.status).json({ error: cihaz.error, code: cihaz.code });

  // Erisilebilir magazalar istek basina bir kez cozulur; boylece rotalar
  // senkron kalir. Yalnizca cok magazali roller icin sorgu atilir.
  req.storeIds = await accessibleStoreIds(req.user);

  // Varsayilan RED kapisi. requireAuth'a konuldu cunku korunan her
  // yonlendirici bundan geciyor: tek kanca tam kapsama veriyor ve yeni bir
  // rota eklendiginde IK'ya kendiliginden acilmiyor.
  if (req.user.role === HR_ROLE && !hrAllows(req.method, req.originalUrl)) {
    return res.status(403).json({
      error: 'İnsan Kaynakları rolü yalnızca mağaza puantajlarını görüntüleyebilir',
    });
  }

  // Alan kapısı (varsayılan RED): mağaza hesabı PDKS'e, barista operasyona
  // giremez. Beyaz liste mantığı burada da geçerli — ileride eklenen bir
  // operasyon rotası baristaya kendiliğinden açılmaz.
  if (!areaAllows(req.user.role, req.method, req.originalUrl)) {
    const area = areaOf(req.method, req.originalUrl);
    return res.status(403).json({ error: AREA_ERRORS[area], code: 'AREA_FORBIDDEN' });
  }

  // Operasyon alani icin ACIK MESAI sarti. Burada, requireOnShift'i her
  // yonlendiriciye tek tek eklemek yerine: kosul req.user'a ihtiyac duyuyor
  // ve requireAuth her korunan yonlendiricinin BASINDA calisiyor, dolayisiyla
  // tek kanca tam kapsama veriyor.
  //
  // KRITIK EMNIYET: magazada PDKS KAPALIYSA sart aranmaz. Aksi halde PDKS'i
  // acmamis bir magazanin personeli giris yapamayacagi icin uygulamanin
  // tamamindan kilitlenirdi — ozelligi acmak calisan bir magazayi bozardi.
  //
  // Maliyet: yalnizca bu iki rol, yalnizca operasyon yollarinda tek ek sorgu.
  if (ON_SHIFT_ROLES.includes(req.user.role) && !shiftExempt(req.originalUrl)) {
    const { pdksEnabled, inside } = await shiftState(req.user.id);
    if (pdksEnabled && !inside) {
      return res.status(403).json({
        error: 'Bu bölüme girmek için önce işe giriş yapmalısınız.',
        // Istemci bunu gorup kullaniciyi Devam Takibi ekranina yonlendiriyor.
        code: 'SHIFT_REQUIRED',
      });
    }
  }
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
  // IK: kademe olarak bolge muduru USTUNDE cunku magaza sinirlarini asan
  // puantaj gorunurlugu tanir; boylece bir bolge muduru kendi bolgesi
  // disini gorebilecek bir IK kullanicisi olusturamaz.
  'hr',
  'regional_manager',
  'store_manager',
  'shift_supervisor',
  // Mağaza hesabı: bir kişi değil, mağazadaki ortak cihazın hesabı. Stok,
  // satış ve zayi işlemleri bu hesaptan yapılır; kimseyi yönetmez.
  'store',
  'barista',
];

const ROLE_LABELS = {
  super_admin: 'Ana Yönetici',
  operations_manager: 'Operations Manager',
  hr: 'İnsan Kaynakları',
  regional_manager: 'Regional Manager',
  store_manager: 'Store Manager',
  shift_supervisor: 'Shift Supervisor',
  store: 'Mağaza',
  barista: 'Barista',
};

/// Uygulamanın iki alanı. İstemcideki iki menü bölümüyle birebir aynı:
///   pdks       -> "PDKS & Kadro" (devam, vardiya, izin, puantaj)
///   operations -> "Operasyon & Denetim" (ürün, satış, zayi, rapor, yönetim)
const AREAS = { PDKS: 'pdks', OPERATIONS: 'operations' };

/// Rolün girebildiği alanlar. Listede olmayan rol iki alana da girer.
///   store   : yalnızca operasyon — kişi olmadığı için mesai/izin tutmaz.
///   barista : yalnızca PDKS — operasyonu mağaza hesabı yürütür.
/// (IK ayrıca kendi beyaz listesiyle daha da daraltılır.)
const ROLE_AREAS = {
  store: [AREAS.OPERATIONS],
  barista: [AREAS.PDKS],
};

/// PDKS'te "personel" sayılmayan roller: çizelge, puantaj, izin ve devam
/// listelerine girmezler, kendilerine vardiya atanamaz.
const NON_PERSONNEL_ROLES = ['store'];

/// PDKS personel listeleri için SQL koşulu. Değerler sabit listeden geldiği
/// için parametre yerine metne gömülmesi güvenli.
function personnelOnly(alias = 'u') {
  const col = alias ? `${alias}.role` : 'role';
  return `AND ${col} NOT IN (${NON_PERSONNEL_ROLES.map((r) => `'${r}'`).join(', ')})`;
}

function roleAreas(role) {
  return ROLE_AREAS[role] || [AREAS.PDKS, AREAS.OPERATIONS];
}

// Her iki alanın da dışında kalan ortak yollar: oturum/profil, giriş ekranı
// görseli ve mağaza adı listesi (profil ekranı mağaza adını gösteriyor).
const SHARED_PATHS = [
  { pattern: /^\/auth(\/|$)/ },
  { pattern: /^\/branding(\/|$)/ },
  { pattern: /^\/health$/ },
  { method: 'GET', pattern: /^\/stores$/ },
];

/// İsteğin ait olduğu alan; ortak yolsa null.
function areaOf(method, originalUrl) {
  const path = normalizePath(originalUrl);
  if (SHARED_PATHS.some((r) => (!r.method || r.method === method) && r.pattern.test(path))) {
    return null;
  }
  return /^\/pdks(\/|$)/.test(path) ? AREAS.PDKS : AREAS.OPERATIONS;
}

/// Rol bu isteğin alanına girebilir mi?
function areaAllows(role, method, originalUrl) {
  const area = areaOf(method, originalUrl);
  return area === null || roleAreas(role).includes(area);
}

const AREA_ERRORS = {
  pdks: 'Mağaza hesabı PDKS & Kadro bölümünü kullanamaz',
  operations: 'Bu hesap Operasyon & Denetim bölümünü kullanamaz',
};

/// Birden fazla magazadan sorumlu olabilen roller; magaza atamasi
/// user_stores tablosundan gelir.
// IK de buraya dahil: kapsami user_stores'tan gelir. Varsayilan olarak TUM
// magazalari vermek yerine atama istenmesi bilincli bir karar — yeni bir role
// kendiliginden her magazanin puantajini acmak guvenli varsayilan degil.
const MULTI_STORE_ROLES = ['operations_manager', 'regional_manager', 'hr'];

/// Kullanici yonetimi yapabilen roller (kendi altindakileri tanimlar).
const MANAGER_ROLES = ['super_admin', 'operations_manager', 'regional_manager', 'store_manager'];

/// IK rolu. Yonetici DEGIL: kullanici/urun/kasa islemlerine hic erismez.
const HR_ROLE = 'hr';

/// Puantaji baskasi adina okuyabilen roller. Yoneticiler + IK.
const TIMESHEET_VIEW_ROLES = [...MANAGER_ROLES, HR_ROLE];

// IK'nin erisebildigi yollar. BEYAZ liste (varsayilan RED) bilincli secim:
// rotalarin cogu yalnizca requireAuth ile korunuyor, kara liste yaklasiminda
// ileride eklenen herhangi bir rota sessizce IK'ya acik olurdu.
//
// Salt okunur: GET disinda tek istisna sifre degistirme.
const HR_ALLOWED = [
  { method: 'GET', pattern: /^\/auth\/me$/ },
  { method: 'POST', pattern: /^\/auth\/password$/ },
  { method: 'GET', pattern: /^\/stores$/ },
  { method: 'GET', pattern: /^\/pdks\/timesheet$/ },
];

/// Istek yolunu /api on ekinden ve sorgu dizesinden arindirir.
function normalizePath(originalUrl) {
  const noQuery = String(originalUrl || '').split('?')[0];
  const noApi = noQuery.startsWith('/api') ? noQuery.slice(4) : noQuery;
  // Sondaki egik cizgi yol eslesmesini bozmasin.
  const trimmed = noApi.replace(/\/+$/, '');
  return trimmed || '/';
}

/// IK istegi beyaz listede mi?
function hrAllows(method, originalUrl) {
  const path = normalizePath(originalUrl);
  return HR_ALLOWED.some((r) => r.method === method && r.pattern.test(path));
}

function roleLevel(role) {
  const i = ROLES.indexOf(role);
  return i < 0 ? ROLES.length : i;
}

/// [actor] rolunun tanimlayabilecegi roller: kendinden asagidakiler.
function assignableRoles(actorRole) {
  // Yonetici olmayan roller kullanici tanimlayamaz. Rotalar bunu zaten
  // engelliyor; burada da kesilmesi ikinci bir emniyet — IK gibi kademesi
  // yuksek ama yonetici olmayan bir rol eklendiginde liste bos kalir.
  if (!MANAGER_ROLES.includes(actorRole)) return [];
  return ROLES.slice(roleLevel(actorRole) + 1);
}

function isMultiStoreRole(role) {
  return MULTI_STORE_ROLES.includes(role);
}

// Ana Yoneticinin mağaza müdürlerine ve personele devredebildiği yetkiler.
// Rol sabit kalır; bu liste rolün üstüne eklenen izinlerdir.
const ALL_PERMISSIONS = ['manage_product_types', 'adjust_batches', 'discard', 'ikram'];

// Yeni kullanıcı zayi ve ikram yapabilir: yetki sistemi gelmeden önceki
// davranış buydu, varsayılanı değiştirmek mevcut akışı kırardı.
const DEFAULT_PERMISSIONS = ['discard', 'ikram'];

const PERMISSION_LABELS = {
  manage_product_types: 'Pasta çeşidi yönetimi',
  adjust_batches: 'Parti düzeltme (tarih/adet)',
  discard: 'Zayi',
  ikram: 'İkram',
};

const PERMISSION_ERRORS = {
  manage_product_types: 'Pasta çeşidi yönetimi yetkiniz yok',
  adjust_batches: 'Parti düzeltme yetkiniz yok',
  discard: 'Zayi girme yetkiniz yok',
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

/// Operasyon alanina erismek icin acik mesai kaydi gereken roller.
///
/// Magaza muduru ve ustu DISARIDA: mudurun vardiya planlamak, onay vermek ve
/// raporlara bakmak icin mesai baslatmasi gerekmiyor; bolge/operasyon muduru
/// ve ana yonetici ise bir magazada mesai tutmuyor.
// Barista artık operasyona hiç girmediği için (ROLE_AREAS) listede yalnızca
// vardiya sorumlusu kaldı.
const ON_SHIFT_ROLES = ['shift_supervisor'];

// Mesai sarti ARANMAYAN yollar. Beyaz liste (varsayilan: sart aranir) bilincli
// secim: ileride eklenen bir operasyon rotasi sarti kendiliginden tasiyor.
//
// /auth  : oturum ve profil — kilit kendini besleyen dongu olmasin.
// /pdks  : giris yapabilmek icin buraya erisilmeli.
const SHIFT_EXEMPT = [/^\/auth(\/|$)/, /^\/pdks(\/|$)/, /^\/health$/];

function shiftExempt(originalUrl) {
  const path = normalizePath(originalUrl);
  return SHIFT_EXEMPT.some((re) => re.test(path));
}

/// Personel mesaide mi? Molada olan da mesaide sayilir: mesai devam ediyor.
///
/// Doner: { required, inside, pdksEnabled }
async function shiftState(userId) {
  const row = await queryOne(`
    SELECT s.pdks_enabled,
           (SELECT al.type FROM attendance_logs al
            WHERE al.user_id = ? ORDER BY al.occurred_at DESC, al.id DESC LIMIT 1) AS last_type
    FROM users u LEFT JOIN stores s ON s.id = u.store_id
    WHERE u.id = ?`, userId, userId);
  const pdksEnabled = !!(row && row.pdks_enabled);
  const inside = !!row && (row.last_type === 'GIRIS' || row.last_type === 'MOLA_BASLA');
  return { pdksEnabled, inside };
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
  HR_ROLE, TIMESHEET_VIEW_ROLES, hrAllows, normalizePath,
  ON_SHIFT_ROLES, shiftExempt, shiftState,
  AREAS, ROLE_AREAS, NON_PERSONNEL_ROLES, personnelOnly, roleAreas, areaOf, areaAllows,
  accessibleStoreIds, allowsStore, resolveStoreScope, storeFilter,
  ALL_PERMISSIONS, DEFAULT_PERMISSIONS, PERMISSION_LABELS, PERMISSION_ERRORS,
  parsePermissions, permissionsOf, serializePermissions, requirePermission,
};
