import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { MoreVertical, ShoppingCart, Gift, Package, Banknote, ShieldCheck, X } from 'lucide-react';
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

// Açık pencerelerin yığını: Escape yalnızca en üstteki pencereyi kapatır
// (ör. form üstünde açılan onay penceresi).
const modalStack = [];

/**
 * Standart pencere — Flutter'daki StandardDialog'un web karşılığı.
 * Telefonda (≤640px) alttan panel, geniş ekranda ortalanmış diyalog.
 * Başlık + 44px kapat düğmesi, kaydırılan gövde, gövdenin sonundaki
 * .form-actions sabit alt bar olur. Escape ve tutamacı aşağı çekmek kapatır;
 * busy iken kapatma kilitlenir. Açıkken sayfa kaydırması durur, odak
 * pencereye taşınır ve kapanınca geri döner.
 */
export function Modal({ title, onClose, children, busy = false, wide = false }) {
  const ref = useRef(null);
  const titleId = useRef(`modal-title-${Math.random().toString(36).slice(2)}`).current;
  const drag = useRef(null);
  const closeRef = useRef(onClose);
  closeRef.current = busy ? null : onClose;

  useEffect(() => {
    const token = {};
    modalStack.push(token);
    const prevFocus = document.activeElement;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const first = ref.current?.querySelector(
      'input:not([type=hidden]):not(:disabled), select:not(:disabled), textarea:not(:disabled)'
    );
    (first || ref.current)?.focus({ preventScroll: true });
    const onKey = (e) => {
      if (e.key === 'Escape' && modalStack[modalStack.length - 1] === token) {
        e.stopPropagation();
        closeRef.current?.();
      }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
      modalStack.splice(modalStack.indexOf(token), 1);
      if (modalStack.length === 0) document.body.style.overflow = prevOverflow;
      if (prevFocus && typeof prevFocus.focus === 'function') prevFocus.focus({ preventScroll: true });
    };
  }, []);

  // Tutamaç/başlık aşağı sürüklenirse panel kapanır (yalnızca dokunmatik
  // panelde anlamlı; masaüstünde başlık sürüklenmez).
  const onPointerDown = (e) => {
    if (e.pointerType === 'mouse' || e.target.closest('button')) return;
    drag.current = { y: e.clientY, dy: 0 };
  };
  const onPointerMove = (e) => {
    if (!drag.current) return;
    drag.current.dy = Math.max(0, e.clientY - drag.current.y);
    ref.current.style.transform = `translateY(${drag.current.dy}px)`;
  };
  const onPointerUp = () => {
    if (!drag.current) return;
    const { dy } = drag.current;
    drag.current = null;
    ref.current.style.transform = '';
    if (dy > 90) closeRef.current?.();
  };

  return createPortal(
    <div
      className="modal-backdrop"
      // mousedown: metin seçerken pencere dışına taşan sürükleme kapatmasın.
      onMouseDown={(e) => { if (e.target === e.currentTarget) closeRef.current?.(); }}
    >
      <div
        ref={ref}
        className={`modal${wide ? ' modal-wide' : ''}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-busy={busy || undefined}
        tabIndex={-1}
      >
        <div
          className="modal-head"
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
        >
          <span className="modal-handle" aria-hidden="true" />
          <h3 id={titleId}>{title}</h3>
          <button
            type="button"
            className="modal-close"
            aria-label="Kapat"
            title="Kapat"
            disabled={busy}
            onClick={() => closeRef.current?.()}
          >
            <X size={20} />
          </button>
        </div>
        <div className="modal-body">{children}</div>
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
  const labels = { frozen: 'Donuk Depo', thawing: 'Çözülme', food_cabinet: 'Food Dolabı', sold: 'Satıldı', discarded: 'Zayi' };
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

// Satis/ikram onayi icin zengin gorsel modal (sat_onayla_modal mockup'ı).
// Her zaman TAM 1 adet duser.
export function SellConfirmModal({ batch: b, kind, onCancel, onConfirm }) {
  const isSale = kind === 'sale';
  const priced = hasPrice(b.product_unit_price);
  return (
    <Modal title={<><ShoppingCart size={17} /> {isSale ? 'Satışı Onayla' : 'İkramı Onayla'}</>} onClose={onCancel}>
      <div className="sell-confirm">
        <div className="sell-confirm-head">
          <span className="icon-chip primary"><Banknote size={18} /></span>
          <div>
            <strong>Kasa İşlemi</strong>
            <p className="muted" style={{ margin: 0, fontSize: 'var(--fs-label)' }}>Stok düşümü ve ciro güncelleme</p>
          </div>
        </div>

        <div className="sell-confirm-product">
          <strong>{b.product_name}</strong>
          {b.urgency && <StatusBadge status="food_cabinet" urgency={b.urgency} />}
        </div>

        <div className="sell-stock-row">
          <span className="icon-chip muted"><Package size={16} /></span>
          <span className="muted">Stok Değişimi</span>
          <span className="sell-stock-change">{b.remaining} Adet → <strong>{b.remaining - 1} Adet</strong> Kalan</span>
        </div>

        <div className="sell-amount-box">
          <div className="sell-amount-label">
            <span className={`icon-chip ${isSale ? 'success' : 'accent'}`}>{isSale ? <Banknote size={18} /> : <Gift size={18} />}</span>
            <div>
              <strong>{isSale ? 'Ciroya Eklenecek Tutar' : 'İkram Değeri'}</strong>
              <p className="muted" style={{ margin: 0, fontSize: 'var(--fs-label)' }}>
                {priced ? `Birim Fiyat: ${fmtMoney(b.product_unit_price)}` : 'Bu çeşit için fiyat tanımlı değil'}
              </p>
            </div>
          </div>
          <strong className="sell-amount-value">{isSale && priced ? '+' : ''}{priced ? fmtMoney(b.product_unit_price) : '0,00 ₺'}</strong>
        </div>

        <p className="sell-confirm-note">
          <ShieldCheck size={14} />
          {isSale
            ? 'Kasa raporuna ve anlık gün sonu cirosuna hemen işlenir.'
            : 'Ciroya eklenmez ve satış adedine sayılmaz; ayrı ikram raporuna işlenir.'}
        </p>

        <div className="form-actions">
          <button className="btn btn-secondary" onClick={onCancel}>Vazgeç</button>
          <button className="btn btn-primary" onClick={onConfirm}>
            1 Adet {isSale ? 'Satışı Yap' : 'İkram Et'}
          </button>
        </div>
      </div>
    </Modal>
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
  // Dinleyici katman kapaliyken null, acikken gosterilecek metni doner.
  const [message, setMessage] = useState(null);
  useEffect(() => subscribeBusy(setMessage), []);
  if (!message) return null;
  return <LoadingOverlay message={message} />;
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
