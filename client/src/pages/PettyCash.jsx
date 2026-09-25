import { useCallback, useEffect, useRef, useState } from 'react';
import { Receipt, Camera, Image as ImageIcon, X } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, Confirm, toast } from '../components/ui';
import { fmtDateTime, fmtDate, fmtMoney, errorMessage } from '../format';

const SPENDER_ROLES = ['store_manager', 'shift_supervisor'];

// Fis gorseli sunucuda en kucuk makul boyutta saklanir: uzun kenar 1280px'e
// indirilir, hedef boyuta inene kadar JPEG kalitesi kademeli dusurulur.
// Flutter tarafindaki encodeReceipt ile ayni davranis.
const RECEIPT_MAX_CHARS = 900000;

function compressReceipt(file, maxSide = 1280) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error('Dosya okunamadı'));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error('Görsel açılamadı'));
      img.onload = () => {
        const scale = Math.min(1, maxSide / Math.max(img.width, img.height));
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(img.width * scale);
        canvas.height = Math.round(img.height * scale);
        canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
        let quality = 0.7;
        let url = canvas.toDataURL('image/jpeg', quality);
        while (url.length > RECEIPT_MAX_CHARS && quality > 0.35) {
          quality -= 0.1;
          url = canvas.toDataURL('image/jpeg', quality);
        }
        resolve(url);
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

const PETTY_STATUS_LABEL = {
  pending: 'Onay bekliyor',
  approved: 'Onaylandı',
  rejected: 'Reddedildi',
};
const PETTY_STATUS_KIND = {
  pending: 'warning',
  approved: 'sold',
  rejected: 'critical',
};

export default function PettyCash() {
  const { user } = useAuth();
  const [items, setItems] = useState([]);
  const [status, setStatus] = useState(null);
  const [showAdd, setShowAdd] = useState(false);
  const [showLimits, setShowLimits] = useState(false);
  const [del, setDel] = useState(null);
  const [receipt, setReceipt] = useState(null);
  const [reload, setReload] = useState(0);

  const canSpend = SPENDER_ROLES.includes(user.role);
  const isSuper = user.role === 'super_admin';

  const load = useCallback(() => {
    api.get('/petty-cash')
      .then((r) => { setItems(r.data.items || []); setStatus(r.data.status || null); })
      .catch(() => {});
  }, []);

  useEffect(() => { load(); }, [load, reload]);

  async function openReceipt(id) {
    try {
      const r = await api.get(`/petty-cash/${id}/receipt`, { busyMessage: 'Fiş açılıyor...' });
      setReceipt(r.data.receipt);
    } catch {
      // Bildirim API katmaninda gosterilir.
    }
  }

  const tight = status && status.weekly_limit > 0
    && status.spent_this_week / status.weekly_limit >= 0.85;

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Receipt size={20} /> Petty Cash</h2>
        <div className="actions">
          {isSuper && (
            <button className="btn btn-secondary" onClick={() => setShowLimits(true)}>Limitler</button>
          )}
          {canSpend && (
            <button className="btn btn-primary" onClick={() => setShowAdd(true)}>+ Masraf Ekle</button>
          )}
        </div>
      </div>

      {status && (status.weekly_limit > 0 ? (
        <div className="surface-panel">
          <div className="petty-head">
            <strong>Bu Hafta</strong>
            <span className="muted">
              {fmtMoney(status.spent_this_week)} / {fmtMoney(status.weekly_limit)}
            </span>
          </div>
          <div className="petty-progress">
            <div
              className={`petty-progress-bar ${tight ? 'danger' : ''}`}
              style={{ width: `${Math.min(100, (status.spent_this_week / status.weekly_limit) * 100)}%` }}
            />
          </div>
          <p className="petty-remaining" style={tight ? { color: 'var(--danger)' } : undefined}>
            Kalan: {fmtMoney(status.remaining)}
          </p>
          {/* Bekleyen masraf da limitten dusuyor: para kasadan cikti. */}
          {status.pending_this_week > 0 && (
            <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
              {fmtMoney(status.pending_this_week)} onay bekliyor ({status.pending_count} kayıt)
              {status.can_approve && ' — Onaylar ekranından karar verebilirsiniz.'}
            </p>
          )}
          <p className="muted" style={{ fontSize: 12, margin: 0 }}>
            Hafta başlangıcı: {fmtDate(status.week_start)}
          </p>
        </div>
      ) : (
        <div className="alert error">
          Bu mağaza için haftalık petty cash limiti tanımlanmamış. Masraf girilebilmesi için
          Ana Yöneticinin limit belirlemesi gerekir.
        </div>
      ))}

      {!canSpend && !isSuper && (
        <div className="alert">
          Masraf girişi yalnızca Store Manager ve Shift Supervisor kullanıcılarına açıktır;
          buradan kayıtları görüntüleyebilirsiniz.
        </div>
      )}

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr><th>Açıklama</th><th>Tutar</th><th>Durum</th><th>Fiş</th><th>Giren</th><th>Tarih</th><th>İşlem</th></tr>
            </thead>
            <tbody>
              {items.length === 0 && (
                <tr><td data-label="" colSpan="7"><p className="empty">Bu hafta masraf kaydı yok.</p></td></tr>
              )}
              {items.map((e) => (
                <tr key={e.id}>
                  <td data-label="Açıklama"><strong>{e.description}</strong></td>
                  <td data-label="Tutar">{fmtMoney(e.amount)}</td>
                  <td data-label="Durum">
                    <span className={`badge ${PETTY_STATUS_KIND[e.status] || 'sold'}`}>
                      {PETTY_STATUS_LABEL[e.status] || 'Onaylandı'}
                    </span>
                    {/* Ret gerekcesi masrafi girene gosterilir. */}
                    {e.status === 'rejected' && e.decision_note && (
                      <div className="muted" style={{ fontSize: 11 }}>{e.decision_note}</div>
                    )}
                  </td>
                  <td data-label="Fiş">
                    {e.has_receipt
                      ? <button className="btn btn-sm btn-secondary" onClick={() => openReceipt(e.id)}>Görüntüle</button>
                      : <span className="muted">yok</span>}
                  </td>
                  <td data-label="Giren">{e.created_by_name || '-'}</td>
                  <td data-label="Tarih" className="muted" style={{ fontSize: 13 }}>{fmtDateTime(e.spent_at)}</td>
                  <td data-label="İşlem">
                    <button className="btn btn-sm btn-outline-danger" onClick={() => setDel(e)}>Sil</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {showAdd && (
        <ExpenseModal
          status={status}
          onClose={() => setShowAdd(false)}
          onDone={() => { setShowAdd(false); setReload((n) => n + 1); }}
        />
      )}

      {showLimits && (
        <LimitsModal
          onClose={() => setShowLimits(false)}
          onDone={() => { setShowLimits(false); setReload((n) => n + 1); }}
        />
      )}

      {del && (
        <Confirm
          title="Masrafı Sil"
          confirmLabel="Sil"
          message={`${fmtMoney(del.amount)} — ${del.description} kaydı silinecek.`}
          onCancel={() => setDel(null)}
          onConfirm={async () => {
            try {
              await api.delete(`/petty-cash/${del.id}`, { successMessage: 'Masraf silindi' });
            } catch {
              // Bildirim API katmaninda gosterilir.
            }
            setDel(null);
            setReload((n) => n + 1);
          }}
        />
      )}

      {receipt && (
        <Modal title="Fiş / Fatura" onClose={() => setReceipt(null)}>
          <img src={receipt} alt="Fiş" style={{ width: '100%', borderRadius: 'var(--radius-sm)' }} />
        </Modal>
      )}
    </div>
  );
}

function ExpenseModal({ status, onClose, onDone }) {
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [receipt, setReceipt] = useState(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const cameraRef = useRef(null);
  const galleryRef = useRef(null);

  async function pick(e) {
    const file = e.target.files && e.target.files[0];
    e.target.value = '';
    if (!file) return;
    setErr('');
    try {
      setReceipt(await compressReceipt(file));
    } catch (er) {
      setErr(er.message || 'Görsel alınamadı');
    }
  }

  async function submit(e) {
    e.preventDefault();
    setErr('');
    const value = Number(String(amount).replace(',', '.'));
    if (!Number.isFinite(value) || value <= 0) { setErr('Tutar 0’dan büyük bir sayı olmalıdır'); return; }
    if (!description.trim()) { setErr('Açıklama zorunludur'); return; }
    if (status && status.weekly_limit > 0 && value > status.remaining) {
      setErr(`Haftalık limit aşılıyor. Kalan: ${fmtMoney(status.remaining)}`);
      return;
    }
    setBusy(true);
    try {
      await api.post('/petty-cash', {
        amount: value, description: description.trim(), receipt,
      }, { noToast: true, busyMessage: 'Masraf kaydediliyor...' });
      toast('Masraf kaydedildi');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="Masraf Ekle" onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        {status && status.weekly_limit > 0 && (
          <p className="muted" style={{ fontSize: 13, marginTop: 0 }}>
            Bu hafta kalan: <strong>{fmtMoney(status.remaining)}</strong>
          </p>
        )}
        <div className="field">
          <label>Tutar (TL)</label>
          <input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="decimal" required />
        </div>
        <div className="field">
          <label>Açıklama</label>
          <textarea rows="2" value={description} onChange={(e) => setDescription(e.target.value)} required />
        </div>
        <div className="field">
          <label>Fiş / Fatura</label>
          {receipt && (
            <div className="receipt-preview">
              <img src={receipt} alt="Fiş önizleme" />
              <button type="button" className="btn btn-sm btn-outline-danger" onClick={() => setReceipt(null)}>
                <X size={14} /> Kaldır
              </button>
              <span className="muted">{Math.round(receipt.length / 1024)} KB olarak kaydedilecek</span>
            </div>
          )}
          <div className="actions">
            <button type="button" className="btn btn-secondary" onClick={() => cameraRef.current.click()}>
              <Camera size={16} /> Çek
            </button>
            <button type="button" className="btn btn-secondary" onClick={() => galleryRef.current.click()}>
              <ImageIcon size={16} /> Galeri
            </button>
          </div>
          {/* capture: telefon tarayicisinda dogrudan kamerayi acar */}
          <input ref={cameraRef} type="file" accept="image/*" capture="environment" onChange={pick} style={{ display: 'none' }} />
          <input ref={galleryRef} type="file" accept="image/*" onChange={pick} style={{ display: 'none' }} />
          <p className="muted" style={{ fontSize: 12, margin: '6px 0 0' }}>
            Görsel otomatik olarak küçültülüp sıkıştırılarak saklanır.
          </p>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Kaydediliyor...' : 'Kaydet'}
          </button>
        </div>
      </form>
    </Modal>
  );
}

function LimitsModal({ onClose, onDone }) {
  const [limits, setLimits] = useState([]);
  const [values, setValues] = useState({});
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api.get('/petty-cash/limits')
      .then((r) => {
        setLimits(r.data);
        setValues(Object.fromEntries(r.data.map((l) => [l.store_id, String(l.weekly_amount)])));
      })
      .catch(() => {});
  }, []);

  async function submit(e) {
    e.preventDefault();
    setErr('');
    setBusy(true);
    try {
      for (const l of limits) {
        const raw = String(values[l.store_id] ?? '').replace(',', '.').trim();
        const value = Number(raw === '' ? '0' : raw);
        if (!Number.isFinite(value) || value < 0) {
          setErr(`${l.store_name}: limit 0 veya daha büyük olmalıdır`);
          return;
        }
        if (value === l.weekly_amount) continue;
        await api.put(`/petty-cash/limits/${l.store_id}`, { weekly_amount: value }, { noToast: true });
      }
      toast('Limitler güncellendi');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="Haftalık Petty Cash Limitleri" onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <p className="muted" style={{ fontSize: 13, marginTop: 0 }}>
          Her mağazanın haftalık harcama tavanı. Hafta pazartesi başlar.
        </p>
        {limits.map((l) => (
          <div className="field" key={l.store_id}>
            <label>{l.store_name}</label>
            <input
              value={values[l.store_id] ?? ''}
              onChange={(e) => setValues((v) => ({ ...v, [l.store_id]: e.target.value }))}
              inputMode="decimal"
            />
          </div>
        ))}
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Kaydediliyor...' : 'Kaydet'}
          </button>
        </div>
      </form>
    </Modal>
  );
}
