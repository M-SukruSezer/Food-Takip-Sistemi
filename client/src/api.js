import axios from 'axios';

export function isNative() {
  return typeof window !== 'undefined' && !!window.Capacitor && window.Capacitor.isNativePlatform();
}

export function getApiBaseUrl() {
  const stored = localStorage.getItem('apiUrl');
  if (stored) return stored;
  return import.meta.env.VITE_API_URL || '/api';
}

export function setApiBaseUrl(url) {
  if (!url || !url.trim()) return;
  let clean = String(url).trim();
  if (!/^https?:\/\//i.test(clean)) clean = 'http://' + clean;
  clean = clean.replace(/\/+$/, '');
  localStorage.setItem('apiUrl', clean);
}

const api = axios.create();

api.interceptors.request.use((config) => {
  config.baseURL = getApiBaseUrl();
  const token = localStorage.getItem('token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  (r) => r,
  (err) => {
    if (err.response && err.response.status === 401) {
      localStorage.removeItem('token');
      if (window.location.pathname !== '/login') window.location.href = '/login';
    }
    return Promise.reject(err);
  }
);

export default api;
