import { useCallback, useEffect, useState } from 'react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, toast } from '../components/ui';
import { fmtDateTime, formatHours, errorMessage } from '../format';
import { ClipboardCheck, Hourglass, Receipt } from 'lucide-react';
import { fmtMoney } from '../format';

const STATUS_LABEL = { pending: 'Bekliyor', approved: 'Onaylandı', rejected: 'Reddedildi', cancelled: 'İptal' };
const STATUS_KIND = { pending: 'warning', approved: 'sold', rejected: 'critical', cancelled: 'discarded' };

export default function Approvals() {
  const { user } = useAuth();
  const [items, setItems] = useState([]);
  const [filter, setFilter] = useState('pending');
  const [storeId, setStoreId] = useState('');
  const [stores, setStores] = useState([]);
  const [rejectItem, setRejectItem] = useState(null);
  const [reload, setReload] = useState(0);

  // Onay bekleyen iki farkli is var: erken aktarim ve vardiya mudurunun
  // girdigi petty cash masrafi. Ayri ekran yerine tek "Onaylar" ekraninda
  // sekme: yonetici bekleyen isleri tek yerde goruyor.
  const canApproveCash = ['store_manager', 'super_admin'].includes(user.role);
  const [tab, setTab] = useState('transfer');
  const [cash, setCash] = useState([]);
  const [cashReject, setCashReject] = useState(null);

  const load = useCallback(() => {
    const q = `?status=${filter}${storeId ? `&storeId=${storeId}` : ''}`;
    api.get('/approvals' + q).then((r) => setItems(r.data)).catch(() => {});
  }, [filter, storeId]);

  useEffect(() => { load(); }, [load, reload]);

  useEffect(() => {
    if (user.role === 'super_admin') api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [user.role]);

  useEffect(() => {
    if (!canApproveCash) return;
    api.get('/petty-cash/pending', { silent: true })
      .then((r) => setCash(r.data))
      .catch(() => {});
  }, [canApproveCash, reload]);

  async function decideCash(item, approve, note) {
    try {
      await api.post(`/petty-cash/${item.id}/${approve ? 'approve' : 'reject'}`,
        note ? { note } : undefined,
        { successMessage: approve
            ? `${fmtMoney(item.amount)} masraf onaylandı`
            : `${fmtMoney(item.amount)} masraf reddedildi` });
    } catch {
      // Bildirim API katmaninda gosterilir.
    }
    setReload((n) => n + 1);
  }

  async function approve(item) {
    try {
      const r = await api.post(`/approvals/${item.id}/approve`, undefined, {
        successMessage: `${item.product_name} food dolabına alındı, SKT başladı`,
      });
      setReload((n) => n + 1);
      return r;
    } catch {
      // Bildirim API katmaninda gosterilir.
      setReload((n) => n + 1);
    }
  }

  const pendingCount = items.filter((i) => i.status === 'pending').length;

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><ClipboardCheck size={20} /> Onaylar</h2>
        {pendingCount + cash.length > 0 && (
          <span className="badge warning">{pendingCount + cash.length} bekleyen</span>
        )}
      </div>

      {canApproveCash && (
        <div className="chip-row" style={{ marginBottom: 12 }}>
          <button type="button" className={`chip ${tab === 'transfer' ? 'chip-on' : ''}`}
            onClick={() => setTab('transfer')}>
            <Hourglass size={14} /> Erken Aktarım{pendingCount > 0 ? ` (${pendingCount})` : ''}
          </button>
          <button type="button" className={`chip ${tab === 'cash' ? 'chip-on' : ''}`}
            onClick={() => setTab('cash')}>
            <Receipt size={14} /> Petty Cash{cash.length > 0 ? ` (${cash.length})` : ''}
          </button>
        </div>
      )}

      {tab === 'cash' && canApproveCash ? (
        <CashApprovals
          items={cash}
          showStore={user.role === 'super_admin'}
          onApprove={(i) => decideCash(i, true)}
          onReject={(i) => setCashReject(i)}
        />
      ) : (
      <>

      <div className="surface-panel">
        <div className="filters">
          <select value={filter} onChange={(e) => setFilter(e.target.value)}>
            <option value="pending">Bekleyenler</option>
            <option value="">Tümü</option>
            <option value="approved">Onaylananlar</option>
            <option value="rejected">Reddedilenler</option>
            <option value="cancelled">İptal Edilenler</option>
          </select>
          {user.role === 'super_admin' && (
            <select value={storeId} onChange={(e) => setStoreId(e.target.value)}>
              <option value="">Tüm Mağazalar</option>
              {stores.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          )}
        </div>

        <p className="muted" style={{ fontSize: 13, margin: '0 0 12px' }}>
          Çözünme süresi (8 saat) dolmadan food dolabına alınmak istenen ürünler burada onaylanır. Onaylanan ürünün SKT süresi onay anından itibaren başlar.
        </p>
      </div>

      {items.length === 0 ? (
        <div className="card"><p className="empty">Kayıt bulunamadı.</p></div>
      ) : (
        <div className="card table-card">
          <div className="table-wrap">
            <table className="responsive">
              <thead>
                <tr>
                  <th>Ürün</th><th>İsteyen</th><th>Neden</th><th>Çözülmeye Kalan</th>
                  {user.role === 'super_admin' && <th>Mağaza</th>}
                  <th>Durum</th><th>İstek Zamanı</th><th>İşlem</th>
                </tr>
              </thead>
              <tbody>
                {items.map((a) => (
                  <tr key={a.id}>
                    <td data-label="Ürün"><strong>{a.product_name}</strong><div className="muted" style={{ fontSize: 12 }}>{a.remaining} adet</div></td>
                    <td data-label="İsteyen">{a.requested_by_name || '-'}</td>
                    <td data-label="Neden" style={{ maxWidth: 220 }}>{a.reason}</td>
                    <td data-label="Çözülmeye Kalan">{a.thaw_remaining_hours !== null ? formatHours(a.thaw_remaining_hours) : '-'}</td>
                    {user.role === 'super_admin' && <td data-label="Mağaza">{a.store_name}</td>}
                    <td data-label="Durum"><span className={`badge ${STATUS_KIND[a.status]}`}>{STATUS_LABEL[a.status]}</span></td>
                    <td data-label="İstek Zamanı" className="muted" style={{ fontSize: 13 }}>{fmtDateTime(a.requested_at)}</td>
                    <td data-label="İşlem">
                      {a.status === 'pending' ? (
                        <div className="actions">
                          <button className="btn btn-sm btn-success" onClick={() => approve(a)}>Onayla</button>
                          <button className="btn btn-sm btn-outline-danger" onClick={() => setRejectItem(a)}>Reddet</button>
                        </div>
                      ) : (
                        <span className="muted" style={{ fontSize: 12 }}>
                          {a.decided_by_name || ''}{a.decision_note ? ` — ${a.decision_note}` : ''}
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      </>
      )}

      {rejectItem && (
        <RejectModal
          item={rejectItem}
          onClose={() => setRejectItem(null)}
          onDone={() => { setRejectItem(null); setReload((n) => n + 1); }}
        />
      )}
      {cashReject && (
        <CashRejectModal
          item={cashReject}
          onClose={() => setCashReject(null)}
          onDone={(note) => { const i = cashReject; setCashReject(null); decideCash(i, false, note); }}
        />
      )}

    </div>
  );
}

function RejectModal({ item, onClose, onDone }) {
  const [note, setNote] = useState('');
  const [err, setErr] = useState('');
  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      await api.post(`/approvals/${item.id}/reject`, { note }, { noToast: true });
      toast('İstek reddedildi, ürün çözülmede kaldı');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }
  return (
    <Modal title="İsteği Reddet" onClose={onClose}>
      <form onSubmit={submit}>
        <p><strong>{item.product_name}</strong> ({item.remaining} adet) çözülme sürecinde kalacak.</p>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Red Nedeni (opsiyonel)</label>
          <textarea rows="2" value={note} onChange={(e) => setNote(e.target.value)} placeholder="örn: Çözülme tamamlanmadan alınamaz" />
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-danger">Reddet</button>
        </div>
      </form>
    </Modal>
  );
}

/// Vardiya mudurunun girdigi, onay bekleyen masraflar.
///
/// Tutar ve aciklama yaninda fisin olup olmadigi da gorunur: fissiz masraf
/// onaylanmadan once sorulmali.
function CashApprovals({ items, showStore, onApprove, onReject }) {
  const [receipt, setReceipt] = useState(null);

  async function showReceipt(item) {
    try {
      const r = await api.get(`/petty-cash/${item.id}/receipt`, { silent: true });
      setReceipt({ item, src: r.data.receipt });
    } catch {
      toast('Fiş görseli alınamadı');
    }
  }

  if (items.length === 0) {
    return (
      <div className="card">
        <p className="empty">Onay bekleyen masraf yok.</p>
      </div>
    );
  }

  return (
    <>
      <div className="surface-panel">
        <p className="muted" style={{ fontSize: 13, margin: 0 }}>
          Vardiya müdürünün girdiği masraflar burada onaylanır. Onaylanmayan masraf
          da haftalık limitten düşer — para kasadan çıkmıştır. Reddedilen masraf
          limite geri eklenir.
        </p>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr>
                <th>Tutar</th><th>Açıklama</th><th>Giren</th>
                {showStore && <th>Mağaza</th>}
                <th>Tarih</th><th>Fiş</th><th>İşlem</th>
              </tr>
            </thead>
            <tbody>
              {items.map((e) => (
                <tr key={e.id}>
                  <td data-label="Tutar"><strong>{fmtMoney(e.amount)}</strong></td>
                  <td data-label="Açıklama" style={{ maxWidth: 240 }}>{e.description}</td>
                  <td data-label="Giren">{e.created_by_name || '-'}</td>
                  {showStore && <td data-label="Mağaza">{e.store_name}</td>}
                  <td data-label="Tarih" className="muted" style={{ fontSize: 13 }}>
                    {fmtDateTime(e.spent_at)}
                  </td>
                  <td data-label="Fiş">
                    {e.has_receipt ? (
                      <button className="btn btn-sm btn-secondary" onClick={() => showReceipt(e)}>
                        Görüntüle
                      </button>
                    ) : (
                      <span className="badge critical">Fiş yok</span>
                    )}
                  </td>
                  <td data-label="İşlem">
                    <div className="actions">
                      <button className="btn btn-sm btn-primary" onClick={() => onApprove(e)}>Onayla</button>
                      <button className="btn btn-sm btn-danger" onClick={() => onReject(e)}>Reddet</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {receipt && (
        <Modal title={`Fiş — ${fmtMoney(receipt.item.amount)}`} onClose={() => setReceipt(null)}>
          <img src={receipt.src} alt="Fiş" style={{ width: '100%', borderRadius: 8 }} />
        </Modal>
      )}
    </>
  );
}

/// Ret gerekcesi zorunlu: sunucu da bos gerekceyi reddediyor.
function CashRejectModal({ item, onClose, onDone }) {
  const [note, setNote] = useState('');
  const [err, setErr] = useState('');

  function submit(e) {
    e.preventDefault();
    if (!note.trim()) { setErr('Ret gerekçesi zorunludur'); return; }
    onDone(note.trim());
  }

  return (
    <Modal title={`Masrafı Reddet — ${fmtMoney(item.amount)}`} onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <p className="muted" style={{ fontSize: 13, margin: '0 0 12px' }}>
          {item.description} — {item.created_by_name}
        </p>
        <div className="field">
          <label>Ret Gerekçesi</label>
          <input value={note} onChange={(e) => setNote(e.target.value)} autoFocus required />
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            Masrafı giren kişi bu gerekçeyi görecek. Tutar haftalık limite geri eklenir.
          </p>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-danger">Reddet</button>
        </div>
      </form>
    </Modal>
  );
}
