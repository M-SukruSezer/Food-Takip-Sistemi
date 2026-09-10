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
