import { useState } from 'react';
import { createPortal } from 'react-dom';
import { fmtMoney, hasPrice } from '../format';

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
