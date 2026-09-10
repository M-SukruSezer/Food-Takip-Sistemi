import { useCallback, useEffect, useState } from 'react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, toast } from '../components/ui';
import { fmtDateTime, formatHours, errorMessage } from '../format';
import { ClipboardCheck } from 'lucide-react';

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

  const load = useCallback(() => {
    const q = `?status=${filter}${storeId ? `&storeId=${storeId}` : ''}`;
    api.get('/approvals' + q).then((r) => setItems(r.data)).catch(() => {});
  }, [filter, storeId]);

  useEffect(() => { load(); }, [load, reload]);

  useEffect(() => {
    if (user.role === 'super_admin') api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [user.role]);

  async function approve(item) {
    try {
      const r = await api.post(`/approvals/${item.id}/approve`);
      toast(`${item.product_name} food dolabına alındı, SKT başladı`);
      setReload((n) => n + 1);
      return r;
    } catch (e) {
      toast(errorMessage(e));
      setReload((n) => n + 1);
    }
  }

  const pendingCount = items.filter((i) => i.status === 'pending').length;

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><ClipboardCheck size={20} /> Erken Aktarım Onayları</h2>
        {pendingCount > 0 && <span className="badge warning">{pendingCount} bekleyen</span>}
      </div>

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

      {rejectItem && (
        <RejectModal
          item={rejectItem}
          onClose={() => setRejectItem(null)}
          onDone={() => { setRejectItem(null); setReload((n) => n + 1); }}
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
      await api.post(`/approvals/${item.id}/reject`, { note });
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
