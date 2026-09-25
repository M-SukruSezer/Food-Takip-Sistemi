export function fmtDateTime(iso) {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '-';
  return d.toLocaleString('tr-TR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

export function fmtDate(iso) {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '-';
  return d.toLocaleDateString('tr-TR', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

export function fmtTime(iso) {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '-';
  return d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
}

export function formatHours(hours) {
  if (hours === null || hours === undefined) return '-';
  if (hours <= 0) return 'Süre doldu';
  if (hours < 24) return `${hours} saat`;
  const d = Math.floor(hours / 24);
  const h = hours % 24;
  return h > 0 ? `${d} gün ${h} saat` : `${d} gün`;
}

// datetime-local girdileri yerel saat, veritabani ise UTC ISO tutar.
export function toLocalInput(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function fromLocalInput(value) {
  if (!value) return null;
  const d = new Date(value);
  if (isNaN(d.getTime())) return null;
  return d.toISOString();
}

export function addDaysIso(iso, days) {
  if (!iso) return null;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return null;
  return new Date(d.getTime() + days * 24 * 3600 * 1000).toISOString();
}

export function fmtMoney(value) {
  if (value === null || value === undefined || value === '') return '-';
  const n = Number(value);
  if (!Number.isFinite(n)) return '-';
  return `${n.toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} TL`;
}

export function hasPrice(value) {
  return value !== null && value !== undefined && value !== '' && Number.isFinite(Number(value));
}

// Öneri listesi food dolabındaki her ürünü döner; "acil" olanlar SKT'ye 48
// saatten az kalanlardır. Bildirim sayacı ve ana sayfa kuyruğu bunları kullanır.
export function isUrgentBatch(b) {
  return !!b && ['expired', 'critical', 'warning'].includes(b.urgency);
}

export function sumRemaining(list) {
  return (list || []).reduce((s, b) => s + (b.remaining || 0), 0);
}

// Rol kademeleri; sunucudaki ROLES ile ayni sirada (ust kademe once).
export const ROLE_ORDER = [
  'super_admin',
  'operations_manager',
  'regional_manager',
  'store_manager',
  'shift_supervisor',
  'barista',
];

export const ROLE_LABELS = {
  super_admin: 'Ana Yönetici',
  operations_manager: 'Operations Manager',
  regional_manager: 'Regional Manager',
  store_manager: 'Store Manager',
  shift_supervisor: 'Shift Supervisor',
  barista: 'Barista',
};

// Birden fazla magazadan sorumlu olabilen roller.
export const MULTI_STORE_ROLES = ['operations_manager', 'regional_manager'];

// Kullanici yonetimi yapabilen roller.
export const MANAGER_ROLES = [
  'super_admin', 'operations_manager', 'regional_manager', 'store_manager',
];

// Tum roller (menu erisimi icin).
export const ALL_ROLES = ROLE_ORDER;

export function roleLevel(role) {
  const i = ROLE_ORDER.indexOf(role);
  return i < 0 ? ROLE_ORDER.length : i;
}

// Bir rolun tanimlayabilecegi roller: kendinden asagi kademedekiler.
export function rolesBelow(role) {
  return ROLE_ORDER.slice(roleLevel(role) + 1);
}

// Ana Yoneticinin devredebildigi yetkiler; sunucudaki ALL_PERMISSIONS ile ayni.
export const ALL_PERMISSIONS = ['manage_product_types', 'adjust_batches', 'discard', 'ikram'];

export const PERMISSION_LABELS = {
  manage_product_types: 'Pasta çeşidi yönetimi',
  adjust_batches: 'Parti düzeltme (tarih/adet)',
  discard: 'İmha',
  ikram: 'İkram',
};

// Yeni kullanici imha ve ikram ile gelir: yetki sistemi oncesi davranis buydu.
export const DEFAULT_PERMISSIONS = ['discard', 'ikram'];

// Arayuz yetkisiz dugmeleri gizler; son sozu sunucu soyler. Ana Yonetici her
// yetkiye sahiptir, listesi bos gelse bile.
export function can(user, permission) {
  if (!user) return false;
  if (user.role === 'super_admin') return true;
  return Array.isArray(user.permissions) && user.permissions.includes(permission);
}

// Bir kullanicinin devredebilecegi yetkiler: kendi sahip olduklari kadar.
export function grantablePermissions(user) {
  if (!user) return [];
  if (user.role === 'super_admin') return [...ALL_PERMISSIONS];
  return ALL_PERMISSIONS.filter((p) => can(user, p));
}

export const STATUS_LABELS = {
  frozen: 'Donuk Depo',
  thawing: 'Çözülme (+4°C)',
  food_cabinet: 'Food Dolabı',
  sold: 'Satıldı',
  discarded: 'İmha Edildi',
};

// Arama icin Turkce duyarsizlastirma: personel telefonda Turkce karakter
// yazmadan da bulabilsin ("cikolata" -> "ÇİKOLATA", "pogaca" -> "POĞAÇA").
// ı harfinin NFD ayrisimi olmadigi icin once elle cevrilir, kalan isaretler
// (ş, ğ, ç, ö, ü ve İ'nin noktasi) NFD ile ayiklanip atilir.
export function normalizeSearch(value) {
  return String(value || '')
    .toLocaleLowerCase('tr')
    .replace(/ı/g, 'i')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

export function errorMessage(err) {
  return (err.response && err.response.data && err.response.data.error) || 'Bir hata oluştu';
}
