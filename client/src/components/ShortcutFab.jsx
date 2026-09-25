import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Zap, X, Snowflake, ReceiptText, ClipboardList, ClipboardCheck } from 'lucide-react';
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

export default function ShortcutFab({ role }) {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const items = shortcutsFor(role);

  // Menu acikken Esc kapatir ve sayfa kaymaz.
  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  if (items.length === 0) return null;

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
                style={{ animationDelay: `${i * 40}ms` }}
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

      {!open && (
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
