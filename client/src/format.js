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

export const ROLE_LABELS = {
  super_admin: 'Ana Yönetici',
  store_manager: 'Mağaza Yöneticisi',
  staff: 'Personel',
};

export const STATUS_LABELS = {
  frozen: 'Donuk Depo',
  thawing: 'Çözülme (+4°C)',
  food_cabinet: 'Food Dolabı',
  sold: 'Satıldı',
  discarded: 'İmha Edildi',
};

export function errorMessage(err) {
  return (err.response && err.response.data && err.response.data.error) || 'Bir hata oluştu';
}
