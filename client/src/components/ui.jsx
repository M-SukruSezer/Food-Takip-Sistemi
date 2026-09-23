import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { MoreVertical } from 'lucide-react';
import { fmtMoney, hasPrice } from '../format';
import { subscribeBusy } from '../busy';

let pushFn = null;

export function ToastHost() {
  const [items, setItems] = useState([]);
  pushFn = (msg) => {
    const id = Date.now() + Math.random();
    setItems((s) => [...s, { id, msg }]);
    setTimeout(() => setItems((s) => s.filter((i) => i.id !== id)), 3000);
  };
  return createPortal(
    <>
      {items.map((i) => (
        <div key={i.id} className="toast">{i.msg}</div>
      ))}
    </>,
    document.body
  );
}

export function toast(msg) {
  if (pushFn) pushFn(msg);
}

export function Modal({ title, onClose, children }) {
  return createPortal(
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>{title}</h3>
        {children}
      </div>
    </div>,
    document.body
  );
}

export function Badge({ kind, children }) {
  return <span className={`badge ${kind || ''}`}>{children}</span>;
}

export function StatusBadge({ status, urgency }) {
  if (status === 'food_cabinet' && urgency === 'expired') return <Badge kind="expired">SKT Geçti</Badge>;
  if (status === 'food_cabinet' && urgency === 'critical') return <Badge kind="critical">SON GÜN</Badge>;
  if (status === 'food_cabinet' && urgency === 'warning') return <Badge kind="warning">Son 2 Gün</Badge>;
  const labels = { frozen: 'Donuk Depo', thawing: 'Çözülme', food_cabinet: 'Food Dolabı', sold: 'Satıldı', discarded: 'İmha' };
  return <Badge kind={status}>{labels[status] || status}</Badge>;
}

export function Confirm({ title, message, onCancel, onConfirm, confirmLabel = 'Onayla', danger = true }) {
  return (
    <Modal title={title} onClose={onCancel}>
      <p>{message}</p>
      <div className="form-actions">
        <button className="btn btn-secondary" onClick={onCancel}>Vazgeç</button>
        <button className={`btn ${danger ? 'btn-danger' : 'btn-primary'}`} onClick={onConfirm}>{confirmLabel}</button>
      </div>
    </Modal>
  );
}

// Satis onay metni. Uc ekranda da ayni: her zaman tam 1 adet dusulur.
export function sellConfirmMessage(b) {
  return (
    <>
      <strong>{b.product_name}</strong> ürününden <strong>1 adet</strong> satılacak.
      {' '}Kalan {b.remaining} adetten {b.remaining - 1} adede düşecek.
      <br />
      {hasPrice(b.product_unit_price)
        ? <>Ciroya <strong>{fmtMoney(b.product_unit_price)}</strong> eklenecek.</>
        : <>Bu çeşit için satış fiyatı tanımlı değil; ciroya 0 TL yazılacak.</>}
    </>
  );
}

// Ikram stoktan duser ama satis sayilmaz: ciroya girmez, satis adedine
// yazilmaz. Personel ikisini karistirmasin diye onay metni bunu soyler.
export function ikramConfirmMessage(b) {
  return (
    <>
      <strong>{b.product_name}</strong> ürününden <strong>1 adet ikram</strong> edilecek.
      {' '}Kalan {b.remaining} adetten {b.remaining - 1} adede düşecek.
      <br />
      Ciroya <strong>eklenmez</strong> ve satış adedine sayılmaz.
      {hasPrice(b.product_unit_price)
        ? <> İkram değeri olarak {fmtMoney(b.product_unit_price)} kaydedilir.</>
        : <> Bu çeşit için fiyat tanımlı olmadığı için ikram değeri kaydedilemez.</>}
    </>
  );
}

// Tablo satirlarindaki ikincil islemleri tek dugmede toplar.
// Menu portal ile body'ye basilir: .table-wrap'in overflow'u onu kirpamaz.
export function ActionMenu({ children, label = 'Diğer işlemler' }) {
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState(null);
  const btnRef = useRef(null);

  useEffect(() => {
    if (!open) return undefined;
    const close = () => setOpen(false);
    document.addEventListener('click', close);
    document.addEventListener('scroll', close, true);
    window.addEventListener('resize', close);
    return () => {
      document.removeEventListener('click', close);
      document.removeEventListener('scroll', close, true);
      window.removeEventListener('resize', close);
    };
  }, [open]);

  function toggle(e) {
    e.stopPropagation();
    const r = btnRef.current.getBoundingClientRect();
    setPos({ top: Math.round(r.bottom + 6), right: Math.max(8, Math.round(window.innerWidth - r.right)) });
    setOpen((v) => !v);
  }

  return (
    <>
      <button
        ref={btnRef}
        type="button"
        className="btn btn-sm btn-secondary action-menu-btn"
        onClick={toggle}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={label}
        title={label}
      >
        <MoreVertical size={16} />
      </button>
      {open && pos && createPortal(
        <div className="action-menu" style={{ top: pos.top, right: pos.right }} role="menu">
          {children}
        </div>,
        document.body
      )}
    </>
  );
}

// Tam ekran yukleme katmani. Portal ile body'ye basilir ve tum ekrani ortuger,
// boylece yukleme bitene kadar hicbir dugmeye basilamaz.
export function LoadingOverlay({ message = 'Yükleniyor...' }) {
  return createPortal(
    <div className="loading-overlay" role="status" aria-live="polite" aria-busy="true">
      <div className="loading-box">
        <span className="spinner" aria-hidden="true" />
        <span>{message}</span>
      </div>
    </div>,
    document.body
  );
}

// Uygulamada bir kez monte edilir; API katmanindaki acik istek sayacini dinler.
// Veri okunurken veya kaydedilirken katmani otomatik acar, islem bitince kapatir.
export function BusyHost() {
  const [busy, setBusy] = useState(false);
  useEffect(() => subscribeBusy(setBusy), []);
  if (!busy) return null;
  return <LoadingOverlay />;
}

// Profil fotosu yoksa ad-soyad bas harfleri gosterilir.
export function Avatar({ user, size = 32, className = '' }) {
  const initials = String(user && user.full_name || '')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0] || '')
    .join('')
    .toLocaleUpperCase('tr');
  const style = { width: size, height: size };
  if (user && user.avatar) {
    return <img className={`avatar ${className}`} style={style} src={user.avatar} alt="" />;
  }
  return (
    <span className={`avatar avatar-initials ${className}`} style={{ ...style, fontSize: Math.round(size * 0.4) }}>
      {initials || '?'}
    </span>
  );
}
