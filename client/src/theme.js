// Tema tercihi. Layout yerine burada durur, boylece Profil ekrani da
// degistirebilir ve tema giris ekraninda da uygulanir (eskiden tema yalnizca
// Layout monte oldugunda uygulaniyordu, bu yuzden login her zaman acik gelirdi).
const KEY = 'theme';
const listeners = new Set();

let current = 'light';
try {
  current = localStorage.getItem(KEY) === 'dark' ? 'dark' : 'light';
} catch {
  current = 'light';
}

function apply() {
  document.documentElement.setAttribute('data-theme', current);
  try { localStorage.setItem(KEY, current); } catch { /* depolama kapali olabilir */ }
  listeners.forEach((fn) => fn(current));
}

export function getTheme() {
  return current;
}

export function setTheme(next) {
  current = next === 'dark' ? 'dark' : 'light';
  apply();
}

export function subscribeTheme(fn) {
  listeners.add(fn);
  fn(current);
  return () => listeners.delete(fn);
}

// Modul yuklenirken kayitli tercih uygulanir.
apply();
