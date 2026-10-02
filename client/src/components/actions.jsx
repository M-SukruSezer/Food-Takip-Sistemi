import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { MoreHorizontal, Plus, Search } from 'lucide-react';

// Uygulamadaki (Flutter) etkilesim kaliplarinin web karsiliklari:
//   Fab / ExpandableFab  sag altta yuzen dugme(ler)
//   SwipeRow             soldan saga kaydirinca acilan Duzenle / Sil
//   SearchField          Oneri listesindeki arama kutusunun aynisi

/**
 * Sag altta yuzen tek dugme. Sayfanin sonuna, son kart dugmenin altinda
 * kalmasin diye bir bosluk birakir. Alt menu acikken onun ustunde durur.
 */
export function Fab({ icon: Icon = Plus, label, onClick, disabled = false }) {
  return (
    <>
      <div className="fab-spacer" aria-hidden="true" />
      {createPortal(
        <div className="fab-stack">
          <button type="button" className="fab fab-extended" onClick={onClick} disabled={disabled}>
            <Icon size={20} /> <span>{label}</span>
          </button>
        </div>,
        document.body,
      )}
    </>
  );
}

/**
 * Tek yuzen dugme; dokununca ustunde islemler acilir, tekrar dokununca ya
 * da bir islem secilince kapanir. actions: [{ label, icon, onClick }]
 */
export function ExpandableFab({ actions, label = 'İşlemler' }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);

  useEffect(() => {
    if (!open) return undefined;
    const close = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('pointerdown', close);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('pointerdown', close);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <>
      <div className="fab-spacer" aria-hidden="true" />
      {createPortal(
        <div className="fab-stack" ref={ref}>
          {open && actions.map((a) => (
            <button
              key={a.label}
              type="button"
              className="fab fab-extended fab-secondary fab-pop"
              onClick={() => { setOpen(false); a.onClick(); }}
            >
              {a.icon && <a.icon size={18} />} <span>{a.label}</span>
            </button>
          ))}
          <button
            type="button"
            className={`fab fab-round${open ? ' fab-open' : ''}`}
            aria-expanded={open}
            aria-label={open ? 'Kapat' : label}
            title={open ? 'Kapat' : label}
            onClick={() => setOpen((v) => !v)}
          >
            <Plus size={24} />
          </button>
        </div>,
        document.body,
      )}
    </>
  );
}

// Ayni anda tek satir acik kalir: yenisi acilinca oncekini kapatir.
let openRow = null;

/**
 * Satir soldan saga kaydirilinca altindaki islemleri acar. Fare ile de
 * suruklenir; fareli cihazlarda ayrica satirin sag ustunde "..." dugmesi
 * cikar (kaydirmayi bilmeyen kullanici da ulasabilsin).
 * actions: [{ label, icon, tone: 'primary'|'info'|'warning'|'danger'|'ink', onClick }]
 */
export function SwipeRow({ actions, children, actionWidth = 76 }) {
  const [offset, setOffset] = useState(0);
  const [dragging, setDragging] = useState(false);
  const drag = useRef(null);
  const justDragged = useRef(false);
  const self = useRef({});
  const max = actionWidth * actions.length;

  const close = () => {
    setOffset(0);
    if (openRow === self.current) openRow = null;
  };
  self.current.close = close;

  const open = () => {
    if (openRow && openRow !== self.current) openRow.close();
    openRow = self.current;
    setOffset(max);
  };

  useEffect(() => () => { if (openRow === self.current) openRow = null; }, []);

  if (actions.length === 0) return children;

  const onPointerDown = (e) => {
    if (e.button !== undefined && e.button !== 0) return;
    drag.current = { x: e.clientX, y: e.clientY, start: offset, moved: false, id: e.pointerId };
  };
  const onPointerMove = (e) => {
    const d = drag.current;
    if (!d) return;
    const dx = e.clientX - d.x;
    const dy = e.clientY - d.y;
    if (!d.moved) {
      // Dikey kaydirma sayfanindir; yalnizca yatay hareket satiri surukler.
      if (Math.abs(dx) < 8 || Math.abs(dx) < Math.abs(dy)) {
        if (Math.abs(dy) > 8) drag.current = null;
        return;
      }
      d.moved = true;
      setDragging(true);
      e.currentTarget.setPointerCapture?.(d.id);
    }
    setOffset(Math.min(max, Math.max(0, d.start + dx)));
  };
  const onPointerUp = () => {
    const d = drag.current;
    drag.current = null;
    if (!d || !d.moved) return;
    // Surukleme bitince tarayici bir de tiklama uretir; o tiklama satiri
    // geri kapatmasin.
    justDragged.current = true;
    setTimeout(() => { justDragged.current = false; }, 0);
    setDragging(false);
    if (offset > max / 2) open(); else close();
  };
  // Surukleme bir tiklama da uretir; karttaki baglantilar tetiklenmesin.
  const onClickCapture = (e) => {
    if (justDragged.current || dragging) {
      e.preventDefault();
      e.stopPropagation();
      justDragged.current = false;
      return;
    }
    // Acik satira dokunmak satiri kapatir (karttaki dugme calismaz).
    if (offset > 0 && !e.target.closest('.swipe-hint')) {
      e.preventDefault();
      e.stopPropagation();
      close();
    }
  };

  return (
    <div className={`swipe-row${offset > 0 ? ' swipe-open' : ''}`}>
      {offset > 0 && (
        <div className="swipe-actions" style={{ width: max }}>
          {actions.map((a) => (
            <button
              key={a.label}
              type="button"
              className={`swipe-action tone-${a.tone || 'primary'}`}
              style={{ width: actionWidth }}
              onClick={() => { close(); a.onClick(); }}
            >
              {a.icon && <a.icon size={20} />}
              <span>{a.label}</span>
            </button>
          ))}
        </div>
      )}
      <div
        className="swipe-content"
        style={{ transform: `translateX(${offset}px)`, transition: dragging ? 'none' : undefined }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onClickCapture={onClickCapture}
      >
        {children}
        <button
          type="button"
          className="swipe-hint"
          aria-label="İşlemler"
          title="İşlemler"
          onClick={(e) => { e.stopPropagation(); if (offset > 0) close(); else open(); }}
        >
          <MoreHorizontal size={18} />
        </button>
      </div>
    </div>
  );
}

/** Oneri Satis Listesi'ndeki arama kutusu. */
export function SearchField({ value, onChange, placeholder = 'Ara...', label }) {
  const filtering = value.trim().length > 0;
  return (
    <div className="filters search-row" style={{ marginBottom: 0 }}>
      <div className="input-wrap search" style={{ flex: 1 }}>
        <span className="in-ico"><Search size={17} /></span>
        <input
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          aria-label={label || placeholder}
        />
      </div>
      {filtering && (
        <button type="button" className="btn btn-sm btn-secondary" onClick={() => onChange('')}>Temizle</button>
      )}
    </div>
  );
}
