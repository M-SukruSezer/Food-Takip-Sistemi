import { useCallback, useEffect, useRef, useState } from 'react';
import { Receipt, Camera, Image as ImageIcon, X, Pencil, Trash2 } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, Confirm, toast } from '../components/ui';
import { fmtDateTime, fmtMoney, errorMessage, toLocalInput, fromLocalInput } from '../format';
import { Fab, SwipeRow } from '../components/actions';

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

// Uygulamadaki masraf kategorileri; aciklamanin basina "[Kategori] " olarak
// yazilir.
export const EXPENSE_CATEGORIES = [
  'Temizlik & Hijyen',
  'Acil Sarf & Süt',
  'Kırtasiye & Fiş',
  'Ulaşım & Kurye',
  'Teknik Bakım',
  'Diğer Giderler',
];

/** "[Kategori] (eski belge notu) aciklama" -> { category, text } */
export function splitExpenseDescription(raw) {
  const m = /^\[(.+?)\]\s*(?:\([^)]*\)\s*)?(.*)$/s.exec(raw || '');
  if (!m) return { category: null, text: raw || '' };
  return { category: EXPENSE_CATEGORIES.includes(m[1]) ? m[1] : null, text: m[2] || '' };
}

/** Tutar alani icin sade gosterim: 150 -> "150", 12.5 -> "12,50". */
function fmtAmountInput(v) {
  return v % 1 === 0 ? String(Math.trunc(v)) : v.toFixed(2).replace('.', ',');
}

function weekRange(weekStart) {
  const start = weekStart ? new Date(weekStart) : null;
  if (!start || isNaN(start.getTime())) return '';
  const end = new Date(start);
  end.setDate(end.getDate() + 6);
  const d = (v) => `${String(v.getDate()).padStart(2, '0')}.${String(v.getMonth() + 1).padStart(2, '0')}`;
  return `${d(start)} – ${d(end)}.${end.getFullYear()}`;
}

/** Haftalik kasa limiti ve bakiye karti (uygulamadaki _LimitCard). */
function LimitCard({ status }) {
  if (!(status.weekly_limit > 0)) {
    return (
      <div className="alert error">
        Bu mağaza için haftalık petty cash limiti tanımlanmamış. Masraf girilebilmesi için
        Ana Yöneticinin limit belirlemesi gerekir.
      </div>
    );
  }
  const ratio = Math.min(1, Math.max(0, status.spent_this_week / status.weekly_limit));
  return (
    <div className="card petty-limit">
      <div className="petty-limit-top">
        <div>
          <span className="petty-limit-label">Haftalık Kasa Limiti</span>
          <strong className="petty-limit-value">{fmtMoney(status.weekly_limit)}</strong>
        </div>
        <div style={{ textAlign: 'right' }}>
          <span className="petty-limit-label">Mevcut Bakiye</span>
          <strong className={`petty-limit-value ${ratio >= 0.85 ? 'danger' : 'ok'}`}>{fmtMoney(status.remaining)}</strong>
        </div>
      </div>
      {/* Iki renkli cubuk: kirmizi harcanan, yesil kalan. */}
      <div className="petty-bar" role="img" aria-label={`Bu hafta limitin %${Math.round(ratio * 100)}'i harcandı`}>
        {ratio > 0 && <span className="spent" style={{ flex: ratio }} />}
        {ratio < 1 && <span className="left" style={{ flex: 1 - ratio }} />}
      </div>
      <div className="petty-limit-foot">
        <span><i className="dot" /> Bu Hafta: <strong>{fmtMoney(status.spent_this_week)}</strong></span>
        <span>Hafta: {weekRange(status.week_start)}</span>
      </div>
      {/* Bekleyen masraf da limitten dusuyor: para kasadan cikti. */}
      {status.pending_this_week > 0 && (
        <p className="text-warning" style={{ fontSize: 'var(--fs-label)', margin: '6px 0 0' }}>
          {fmtMoney(status.pending_this_week)} onay bekliyor ({status.pending_count} kayıt)
        </p>
      )}
    </div>
  );
}

export default function PettyCash() {
  const { user } = useAuth();
  const [items, setItems] = useState([]);
  const [status, setStatus] = useState(null);
  const [searchParams, setSearchParams] = useSearchParams();
  const [form, setForm] = useState(null); // { expense? }
  const [showLimits, setShowLimits] = useState(false);
  const [del, setDel] = useState(null);
  const [approve, setApprove] = useState(null);
  const [reject, setReject] = useState(null);
  const [receipt, setReceipt] = useState(null);
  const [reload, setReload] = useState(0);

  const canSpend = SPENDER_ROLES.includes(user.role);
  const isSuper = user.role === 'super_admin';
  // Duzenle / Sil: Ana Yonetici her kayitta, digerleri yalnizca kendi
  // girdigi ve henuz onay bekleyen kayitta (sunucu kurali ile ayni).
  const canModify = (e) => isSuper || (e.status === 'pending' && Number(e.created_by) === Number(user.id));

  const load = useCallback(() => {
    api.get('/petty-cash')
      .then((r) => { setItems(r.data.items || []); setStatus(r.data.status || null); })
      .catch(() => {});
  }, []);

  // Kisayol dugmesinden ?new=1 ile gelindiginde form kendiliginden acilir.
  // Parametre hemen temizlenir, yoksa yenilemede form tekrar aciliyor.
  useEffect(() => {
    if (searchParams.get('new') !== '1') return;
    setForm({});
    const next = new URLSearchParams(searchParams);
    next.delete('new');
    setSearchParams(next, { replace: true });
  }, [searchParams, setSearchParams]);

  useEffect(() => { load(); }, [load, reload]);

  async function openReceipt(id) {
    try {
      const r = await api.get(`/petty-cash/${id}/receipt`, { busyMessage: 'Fiş açılıyor...' });
      setReceipt(r.data.receipt);
    } catch {
      // Bildirim API katmaninda gosterilir.
    }
  }

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Receipt size={20} /> Petty Cash</h2>
      </div>

      {status && <LimitCard status={status} />}

      {isSuper && (
        <div className="card petty-admin">
          <span className="muted">Mağazaların haftalık limitlerini buradan belirleyin.</span>
          <button className="btn btn-sm btn-secondary" onClick={() => setShowLimits(true)}>Limitler</button>
        </div>
      )}

      {!canSpend && !isSuper && (
        <div className="alert">
          Masraf girişi yalnızca Store Manager ve Shift Supervisor kullanıcılarına açıktır;
          buradan kayıtları görüntüleyebilirsiniz.
        </div>
      )}

      {items.length === 0 ? (
        <div className="card"><p className="empty">Bu hafta masraf kaydı yok.</p></div>
      ) : (
        <div className="swipe-list">
          {items.map((e) => {
            const { category, text } = splitExpenseDescription(e.description);
            return (
              <SwipeRow
                key={e.id}
                actions={canModify(e) ? [
                  { label: 'Düzenle', icon: Pencil, tone: 'primary', onClick: () => setForm({ expense: e }) },
                  { label: 'Sil', icon: Trash2, tone: 'danger', onClick: () => setDel(e) },
                ] : []}
              >
                <article className="card petty-item">
                  <div className="petty-item-head">
                    <strong>{text}</strong>
                    <span className="petty-amount">{fmtMoney(e.amount)}</span>
                  </div>
                  <div className="chip-row" style={{ gap: 6 }}>
                    <span className={`badge ${PETTY_STATUS_KIND[e.status] || 'sold'}`}>
                      {PETTY_STATUS_LABEL[e.status] || 'Onaylandı'}
                    </span>
                    {category && <span className="badge info">{category}</span>}
                    {e.has_receipt
                      ? <span className="badge sold">fişli</span>
                      : <span className="badge">fiş yok</span>}
                    {isSuper && e.store_name && <span className="badge info">{e.store_name}</span>}
                  </div>
                  {/* Ret gerekcesi masrafi girene gosterilir. */}
                  {e.status === 'rejected' && e.decision_note && (
                    <p className="text-danger" style={{ fontSize: 'var(--fs-label)', margin: '6px 0 0' }}>
                      Ret gerekçesi: {e.decision_note}
                    </p>
                  )}
                  <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '6px 0 0' }}>
                    {fmtDateTime(e.spent_at)} · {e.created_by_name || 'bilinmiyor'}
                  </p>
                  <div className="actions" style={{ marginTop: 10 }}>
                    <button className="btn btn-sm btn-secondary" disabled={!e.has_receipt} onClick={() => openReceipt(e.id)}>
                      Fişi Gör
                    </button>
                    {e.status === 'pending' && status?.can_approve && (
                      <>
                        <button className="btn btn-sm btn-primary" onClick={() => setApprove(e)}>Onayla</button>
                        <button className="btn btn-sm btn-outline-danger" onClick={() => setReject(e)}>Reddet</button>
                      </>
                    )}
                  </div>
                </article>
              </SwipeRow>
            );
          })}
        </div>
      )}

      {canSpend && <Fab label="Masraf Ekle" onClick={() => setForm({})} />}

      {form && (
        <ExpenseModal
          status={status}
          expense={form.expense}
          onClose={() => setForm(null)}
          onDone={() => { setForm(null); setReload((n) => n + 1); }}
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
          message={`${fmtMoney(del.amount)} — ${splitExpenseDescription(del.description).text} kaydı silinecek.`}
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

      {approve && (
        <Confirm
          title="Masrafı Onayla"
          confirmLabel="Onayla"
          danger={false}
          message={`${fmtMoney(approve.amount)} — ${splitExpenseDescription(approve.description).text}. `
            + `${approve.created_by_name || 'bilinmiyor'} girdi.${approve.has_receipt ? '' : ' Bu masrafta fiş görseli yok.'}`}
          onCancel={() => setApprove(null)}
          onConfirm={async () => {
            try {
              await api.post(`/petty-cash/${approve.id}/approve`, null, { successMessage: 'Masraf onaylandı' });
            } catch {
              // Bildirim API katmaninda gosterilir.
            }
            setApprove(null);
            setReload((n) => n + 1);
          }}
        />
      )}

      {reject && (
        <RejectModal
          expense={reject}
          onClose={() => setReject(null)}
          onDone={() => { setReject(null); setReload((n) => n + 1); }}
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

function RejectModal({ expense, onClose, onDone }) {
  const [note, setNote] = useState('');
  const [err, setErr] = useState('');
  async function submit(e) {
    e.preventDefault();
    if (!note.trim()) { setErr('Ret gerekçesi zorunludur'); return; }
    try {
      await api.post(`/petty-cash/${expense.id}/reject`, { note: note.trim() }, { noToast: true });
      toast('Masraf reddedildi');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }
  return (
    <Modal title="Masrafı Reddet" onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Ret Gerekçesi</label>
          <textarea rows="3" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Masrafı giren kişi bu gerekçeyi görür." />
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-danger">Reddet</button>
        </div>
      </form>
    </Modal>
  );
}

/**
 * Masraf ekleme / duzenleme formu (standart form). Limit karti formda degil
 * sayfada; limit asimi yine burada gonderimden once yakalanir.
 */
function ExpenseModal({ status, expense, onClose, onDone }) {
  const editing = !!expense;
  const parsed = editing ? splitExpenseDescription(expense.description) : null;
  const [amount, setAmount] = useState(editing ? fmtAmountInput(Number(expense.amount)) : '');
  const [spentAt, setSpentAt] = useState(toLocalInput(editing ? expense.spent_at : new Date().toISOString()));
  const [category, setCategory] = useState(parsed?.category || EXPENSE_CATEGORIES[0]);
  const [description, setDescription] = useState(parsed?.text || '');
  const [receipt, setReceipt] = useState(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const cameraRef = useRef(null);
  const galleryRef = useRef(null);

  function addPreset(v) {
    const cur = Number(String(amount).replace(',', '.')) || 0;
    setAmount(fmtAmountInput(cur + v));
  }

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
    // Duzenlemede kaydin kendi tutari limite geri eklenir.
    const available = status && status.weekly_limit > 0
      ? status.remaining + (editing ? Number(expense.amount) : 0)
      : null;
    if (available != null && value > available) {
      setErr(`Haftalık limit aşılıyor. Kalan: ${fmtMoney(available)}`);
      return;
    }
    const body = {
      amount: value,
      description: `[${category}] ${description.trim()}`,
      spent_at: fromLocalInput(spentAt) || undefined,
    };
    // Duzenlemede yeni fis secilmediyse mevcut fis korunur.
    if (receipt) body.receipt = receipt;
    else if (!editing) body.receipt = null;
    setBusy(true);
    try {
      if (editing) {
        await api.put(`/petty-cash/${expense.id}`, body, { noToast: true, busyMessage: 'Masraf kaydediliyor...' });
        toast('Masraf güncellendi');
      } else {
        await api.post('/petty-cash', body, { noToast: true, busyMessage: 'Masraf kaydediliyor...' });
        toast('Masraf kaydedildi');
      }
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title={editing ? 'Masrafı Düzenle' : 'Masraf Ekle'} onClose={onClose} busy={busy}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <div className="form-two">
          <div className="field">
            <label>Tutar (₺)</label>
            <input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="decimal" placeholder="0,00" required />
          </div>
          <div className="field">
            <label>Tarih</label>
            <input type="datetime-local" value={spentAt} onChange={(e) => setSpentAt(e.target.value)} required />
          </div>
        </div>
        <div className="petty-presets">
          {[50, 100, 250, 500].map((p) => (
            <button key={p} type="button" className="btn btn-sm btn-secondary" onClick={() => addPreset(p)}>+{p} TL</button>
          ))}
        </div>
        <div className="field">
          <label>Kategori</label>
          <select value={category} onChange={(e) => setCategory(e.target.value)}>
            {EXPENSE_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
        <div className="field">
          <label>Açıklama</label>
          <textarea rows="2" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Ne için harcandı?" required />
        </div>
        <div className="field">
          <label>Fiş / Fatura Fotoğrafı</label>
          {receipt && (
            <div className="receipt-preview">
              <img src={receipt} alt="Fiş önizleme" />
              <button type="button" className="btn btn-sm btn-outline-danger" onClick={() => setReceipt(null)}>
                <X size={14} /> Kaldır
              </button>
            </div>
          )}
          <div className="petty-presets two">
            <button type="button" className="btn btn-secondary" onClick={() => galleryRef.current.click()}>
              <ImageIcon size={16} /> Galeriden
            </button>
            <button type="button" className="btn btn-secondary" onClick={() => cameraRef.current.click()}>
              <Camera size={16} /> Fotoğraf Çek
            </button>
          </div>
          {/* capture: telefon tarayicisinda dogrudan kamerayi acar */}
          <input ref={cameraRef} type="file" accept="image/*" capture="environment" onChange={pick} style={{ display: 'none' }} />
          <input ref={galleryRef} type="file" accept="image/*" onChange={pick} style={{ display: 'none' }} />
          {editing && expense.has_receipt && !receipt && (
            <p className="login-hint">Mevcut fiş korunur; yenisini seçerseniz değiştirilir.</p>
          )}
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose} disabled={busy}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Kaydediliyor...' : (editing ? 'Kaydet' : 'Masrafı Kaydet')}
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
        <p className="muted" style={{ fontSize: 'var(--fs-body)', marginTop: 0 }}>
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
