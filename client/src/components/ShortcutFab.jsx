import { useEffect, useState } from 'react';
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom';
import {
  Zap, X, Snowflake, ReceiptText, ClipboardList, ClipboardCheck, Plus,
} from 'lucide-react';
import { MANAGER_ROLES, ALL_ROLES, REPORT_PANEL_ROLES } from '../format';

// Sag altta duran kisayol dugmesi. Dokununca tam ekran perde acilir ve
// kisayollar dugmenin uzerinde listelenir. Perde yukleme katmaniyla ayni
// gorunumu paylasir (.app-scrim, .loading-overlay ile ayni zemin ve bulanti).

// Masraf girisi yalnizca magaza kasasini kullanan iki rolde (sunucudaki
// SPENDER_ROLES ile ayni). Ust kademeler modulu gorur ama giris yapmaz.
const SPENDER_ROLES = ['store_manager', 'shift_supervisor'];

const SHORTCUTS = [
  { key: 'batch', label: 'Donuk Depoya Ürün Ekle', ico: Snowflake, roles: ALL_ROLES, to: '/batches', action: 'add' },
  { key: 'expense', label: 'Masraf Gir', ico: ReceiptText, roles: SPENDER_ROLES, to: '/petty-cash', action: 'add' },
  { key: 'report', label: 'Günlük Rapor Gir', ico: ClipboardList, roles: REPORT_PANEL_ROLES, to: '/daily-report', action: 'add' },
  { key: 'approvals', label: 'Onaylar', ico: ClipboardCheck, roles: MANAGER_ROLES, to: '/approvals' },
];

export function shortcutsFor(role) {
  return SHORTCUTS.filter((s) => s.roles.includes(role));
}

// Modulun KENDI birincil islemi. Ana sayfada kisayol menusu acilir; bir
// modulun icindeyken dugme o modulun islemine doner, cunku orada kullanicinin
// isteyecegi sey neredeyse her zaman "bu listeye yeni kayit".
//
// Yalnizca ?new=1 ile form acan sayfalar burada: mekanizma o sayfalarda zaten
// var ve calistigi dogrulandi. Diger moduller kisayol menusune duser, boylece
// dugme hicbir ekranda islevsiz kalmiyor.
const MODUL_EYLEMI = {
  '/batches': { label: 'Yeni Ürün', ico: Plus, roles: ALL_ROLES },
  '/petty-cash': { label: 'Masraf Gir', ico: ReceiptText, roles: SPENDER_ROLES },
  '/daily-report': { label: 'Günlük Rapor Gir', ico: ClipboardList, roles: REPORT_PANEL_ROLES },
};

/// Bulunulan yolun birincil islemi; yoksa null.
export function modulEylemi(pathname, role) {
  const e = MODUL_EYLEMI[pathname];
  return e && e.roles.includes(role) ? e : null;
}

export default function ShortcutFab({ role }) {
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const [searchParams, setSearchParams] = useSearchParams();
  const [open, setOpen] = useState(false);
  const items = shortcutsFor(role);
  // Bulundugumuz modulun kendi islemi varsa dugme menu yerine dogrudan onu
  // yapiyor.
  const eylem = modulEylemi(pathname, role);

  // Menu acikken Esc kapatir ve sayfa kaymaz.
  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  if (items.length === 0 && !eylem) return null;

  /// Bulundugumuz sayfada giris formunu acar.
  ///
  /// Yeni bir yola gitmiyoruz: ayni yola ?new=1 ekliyoruz. Sayfalar bu
  /// parametreyi gorup formu aciyor ve sonra parametreyi temizliyor, bu yuzden
  /// dugme ust uste basildiginda da calisiyor.
  function moduldeAc() {
    const next = new URLSearchParams(searchParams);
    next.set('new', '1');
    setSearchParams(next, { replace: true });
  }

  // Kisayol ilgili ekrani acar; ?new=1 o ekranda giris formunu aciyor.
  function go(item) {
    setOpen(false);
    navigate(item.action === 'add' ? `${item.to}?new=1` : item.to);
  }

  return (
    <>
      {open && (
        <div
          className="app-scrim shortcut-scrim"
          onClick={() => setOpen(false)}
          role="presentation"
        >
          <div className="shortcut-list" onClick={(e) => e.stopPropagation()}>
            {items.map((s, i) => (
              <button
                type="button"
                key={s.key}
                className="shortcut-item"
                // Basamak ters yonde: dugmeye en yakin oge ilk girer.
                // Olculen sorun: i*40ms + 180ms ile en ust oge 300ms'de
                // tamamlaniyordu. Simdi en fazla 60 + 110 = 170ms.
                style={{ animationDelay: `${(items.length - 1 - i) * 20}ms` }}
                onClick={() => go(s)}
              >
                <span className="shortcut-label">{s.label}</span>
                <span className="shortcut-ico"><s.ico size={20} /></span>
              </button>
            ))}
            <button
              type="button"
              className="fab fab-close"
              onClick={() => setOpen(false)}
              aria-label="Kısayolları kapat"
            >
              <X size={22} />
            </button>
          </div>
        </div>
      )}

      {!open && eylem && (
        <button
          type="button"
          className="fab fab-action"
          onClick={moduldeAc}
          aria-label={eylem.label}
          title={eylem.label}
        >
          <eylem.ico size={22} />
          <span className="fab-label">{eylem.label}</span>
        </button>
      )}

      {!open && !eylem && (
        <button
          type="button"
          className="fab"
          onClick={() => setOpen(true)}
          aria-label="Kısayollar"
          title="Kısayollar"
        >
          <Zap size={22} />
        </button>
      )}
    </>
  );
}
