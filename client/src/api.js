import axios from 'axios';
import { beginBusy, endBusy } from './busy';
import { toast } from './components/ui';
import { errorMessage } from './format';

export function isNative() {
  return typeof window !== 'undefined' && !!window.Capacitor && window.Capacitor.isNativePlatform();
}

const configuredApiUrl = import.meta.env.VITE_API_URL || '';

// Derlemede sabit bir API adresi verilmisse kullanicidan sunucu adresi istenmez.
export function hasFixedApiUrl() {
  return !!configuredApiUrl;
}

export function getApiBaseUrl() {
  // Sabit adres varsa, eski kurulumlardan kalan kayitli adres yok sayilir.
  if (configuredApiUrl) return configuredApiUrl;
  const stored = localStorage.getItem('apiUrl');
  if (stored) return stored;
  return '/api';
}

export function setApiBaseUrl(url) {
  if (!url || !url.trim()) return;
  let clean = String(url).trim();
  if (!/^https?:\/\//i.test(clean)) clean = 'http://' + clean;
  clean = clean.replace(/\/+$/, '');
  localStorage.setItem('apiUrl', clean);
}

const api = axios.create();

const MUTATIONS = ['post', 'put', 'patch', 'delete'];

function isMutation(config) {
  return MUTATIONS.includes(String(config && config.method || '').toLowerCase());
}

// Her istek yukleme katmanini acar ve sonucunu bildirime cevirir.
// Istek bazinda ayarlar:
//   silent: true          -> katman ve bildirim yok (arka plan yenilemeleri)
//   noToast: true         -> katman var, bildirim yok (hatayi kendi gosteren ekranlar)
//   successMessage: '...' -> basari bildiriminde genel metin yerine bu kullanilir
//   busyMessage: '...'    -> yukleme katmaninda genel metin yerine bu yazar
api.interceptors.request.use((config) => {
  config.baseURL = getApiBaseUrl();
  const token = localStorage.getItem('token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  if (!config.silent) {
    config.__busy = true;
    beginBusy(config.busyMessage);
  }
  return config;
});

api.interceptors.response.use(
  (response) => {
    if (response.config && response.config.__busy) endBusy();
    const config = response.config || {};
    // Veri okumalarinda basari bildirimi verilmez; her sayfa acilisinda
    // bildirim cikmasi gurultu olurdu. Yazma islemlerinde verilir.
    if (!config.silent && !config.noToast && isMutation(config)) {
      toast(config.successMessage || 'İşlem başarılı');
    }
    return response;
  },
  (err) => {
    if (err.config && err.config.__busy) endBusy();
    const config = err.config || {};
    const unauthorized = err.response && err.response.status === 401;

    if (!config.silent && !config.noToast) {
      toast(errorMessage(err) || 'Hata oluştu');
    }

    if (unauthorized) {
      localStorage.removeItem('token');
      if (window.location.pathname !== '/login') window.location.href = '/login';
    }

    // Sunucu "once ise giris yapmalisiniz" dediyse kullaniciyi Devam Takibi
    // ekranina goturuyoruz. Yoksa personel bos bir operasyon ekraniyla kalir
    // ve ne yapmasi gerektigini bilemez.
    //
    // Yonlendirme YALNIZCA sunucunun verdigi koda gore: istemcide mesai
    // durumunu tahmin etmek iki tarafin ayrismasi demekti.
    if (err.response && err.response.status === 403
        && err.response.data && err.response.data.code === 'SHIFT_REQUIRED'
        && window.location.pathname !== '/pdks') {
      window.location.href = '/pdks?shift=1';
    }
    return Promise.reject(err);
  }
);

export default api;
