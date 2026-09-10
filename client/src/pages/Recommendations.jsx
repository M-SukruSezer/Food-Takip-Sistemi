import { useCallback, useEffect, useMemo, useState } from 'react';
import { Flame } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Confirm, Modal, toast } from '../components/ui';
import { fmtDateTime, errorMessage } from '../format';

export default function Recommendations() {
  const { user } = useAuth();
  const [items, setItems] = useState([]);
  const [reload, setReload] = useState(0);
  const [sellBatch, setSellBatch] = useState(null);
  const [confirmDiscard, setConfirmDiscard] = useState(null);

  const load = useCallback(() => {
    api.get('/recommendations').then((r) => setItems(r.data)).catch(() => {});
  }, []);

  useEffect(() => { load(); }, [load, reload]);

  const grouped = useMemo(() => {
    const critical = items.filter((i) => i.urgency === 'critical' || i.urgency === 'expired');
    const warning = items.filter((i) => i.urgency === 'warning');
    return { critical, warning };
  }, [items]);

  const expired = items.filter((i) => i.urgency === 'expired');

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Flame size={20} /> Öneri Satış Listesi</h2>
        <span className="muted">SKT'ye son 2 gün kalan ürünler</span>
      </div>

      {expired.length > 0 && (
        <div className="alert error">
          <strong>{expired.reduce((s, i) => s + i.remaining, 0)} adet</strong> ürünün SKT'si doldu. Lütfen imha edin veya satışı durdurun.
        </div>
      )}

      <div className="surface-panel">
        <div className="grid stats" style={{ gridTemplateColumns: 'repeat(2, 1fr)' }}>
          <div className="stat stat-card">
            <div className="label"><span><span className="dot dot-red" />Son Gün (0-24 saat)</span></div>
            <div className="value" style={{ color: 'var(--danger)' }}>{grouped.critical.reduce((s, i) => s + i.remaining, 0)}</div>
            <div className="sub">{grouped.critical.length} kayıt öncelikli</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span><span className="dot dot-orange" />1-2 Gün Kalan</span></div>
            <div className="value" style={{ color: 'var(--warning)' }}>{grouped.warning.reduce((s, i) => s + i.remaining, 0)}</div>
            <div className="sub">{grouped.warning.length} kayıt</div>
          </div>
        </div>
      </div>

      {items.length === 0 ? (
        <div className="card"><p className="empty">Öneri listesi boş. Food dolabında SKT'ye 2 günden az kalan ürün yok.</p></div>
      ) : (
        <div className="recommendation-list">
          {items.map((b) => (
            <article key={b.id} className={`recommendation-card ${b.urgency}`}>
              <div className="recommendation-main">
                <div className="recommendation-title">
                  <strong>{b.product_name}</strong>
                  {b.urgency === 'expired'
                    ? <span className="badge expired">SKT Geçti</span>
                    : b.urgency === 'critical'
                      ? <span className="badge critical">SON GÜN</span>
                      : <span className="badge warning">Son 2 Gün</span>}
                </div>
                <div className="recommendation-meta">
                  <span>{b.remaining} adet</span>
                  <span>SKT: {fmtDateTime(b.skt_end)}</span>
                  <span><strong>{b.days_left} gün</strong> ({Math.floor(b.remaining_hours)} sa)</span>
                  {user.role === 'super_admin' && <span>{b.store_name}</span>}
                </div>
              </div>
              <div className="actions recommendation-actions">
                {b.urgency !== 'expired' && (
                  <button className="btn btn-sm btn-success" onClick={() => setSellBatch(b)}>Satış</button>
                )}
                <button className="btn btn-sm btn-outline-danger" onClick={() => setConfirmDiscard(b)}>İmha</button>
              </div>
            </article>
          ))}
        </div>
      )}

      <p className="muted" style={{ fontSize: 13 }}>
        Liste anlıktır: satış işaretlendiğinde stok azalır, tükenen ürünler listeden otomatik düşer.
      </p>

      {sellBatch && (
        <RecSellModal
          batch={sellBatch}
          onClose={() => setSellBatch(null)}
          onDone={() => { setSellBatch(null); setReload((n) => n + 1); }}
        />
      )}

      {confirmDiscard && (
        <Confirm
          title="İmha Et"
          message={`${confirmDiscard.product_name} (${confirmDiscard.remaining} adet) imha edilecek. Onaylıyor musunuz?`}
          confirmLabel="İmha Et"
          onCancel={() => setConfirmDiscard(null)}
          onConfirm={async () => {
            try {
              await api.post(`/batches/${confirmDiscard.id}/discard`, { reason: 'SKT süresi doldu' });
              toast('Ürün imha edildi');
            } catch (e) {
              toast(errorMessage(e));
            }
            setConfirmDiscard(null);
            setReload((n) => n + 1);
          }}
        />
      )}
    </div>
  );
}

function RecSellModal({ batch, onClose, onDone }) {
  const [quantity, setQuantity] = useState(batch.remaining);
  const [err, setErr] = useState('');
  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      await api.post(`/batches/${batch.id}/sell`, { quantity });
      toast('Satış işaretlendi');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }
  return (
    <Modal title="Satış İşaretle" onClose={onClose}>
      <form onSubmit={submit}>
        <p><strong>{batch.product_name}</strong> — SKT: {fmtDateTime(batch.skt_end)} · Kalan: {batch.remaining} adet</p>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Satılan Adet</label>
          <input type="number" min="1" max={batch.remaining} value={quantity} onChange={(e) => setQuantity(e.target.value)} required />
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-success">Satışı Kaydet</button>
        </div>
      </form>
    </Modal>
  );
}
