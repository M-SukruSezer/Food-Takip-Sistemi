import { useCallback, useEffect, useMemo, useState } from 'react';
import { Flame } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Confirm, toast } from '../components/ui';
import { fmtDateTime, errorMessage, fmtMoney, hasPrice } from '../format';

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
    const normal = items.filter((i) => i.urgency === 'normal');
    return { critical, warning, normal };
  }, [items]);

  const expired = items.filter((i) => i.urgency === 'expired');
  const sum = (list) => list.reduce((s, i) => s + i.remaining, 0);

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Flame size={20} /> Öneri Satış Listesi</h2>
        <span className="muted">Food dolabındaki tüm ürünler, SKT'si en yakın olan en üstte</span>
      </div>

      {expired.length > 0 && (
        <div className="alert error">
          <strong>{sum(expired)} adet</strong> ürünün SKT'si doldu. Lütfen imha edin veya satışı durdurun.
        </div>
      )}

      <div className="surface-panel">
        <div className="grid stats" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
          <div className="stat stat-card">
            <div className="label"><span><span className="dot dot-red" />Son Gün (0-24 saat)</span></div>
            <div className="value" style={{ color: 'var(--danger)' }}>{sum(grouped.critical)}</div>
            <div className="sub">{grouped.critical.length} kayıt öncelikli</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span><span className="dot dot-orange" />1-2 Gün Kalan</span></div>
            <div className="value" style={{ color: 'var(--warning)' }}>{sum(grouped.warning)}</div>
            <div className="sub">{grouped.warning.length} kayıt</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span><span className="dot dot-green" />2 Günden Fazla</span></div>
            <div className="value" style={{ color: 'var(--success)' }}>{sum(grouped.normal)}</div>
            <div className="sub">{grouped.normal.length} kayıt</div>
          </div>
        </div>
      </div>

      {items.length === 0 ? (
        <div className="card"><p className="empty">Food dolabında satışa hazır ürün bulunmuyor.</p></div>
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
                      : b.urgency === 'warning'
                        ? <span className="badge warning">Son 2 Gün</span>
                        : <span className="badge food_cabinet">Food Dolabı</span>}
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
        <Confirm
          title="Satışı Onayla"
          danger={false}
          confirmLabel="1 Adet Sat"
          message={sellMessage(sellBatch)}
          onCancel={() => setSellBatch(null)}
          onConfirm={async () => {
            try {
              await api.post(`/batches/${sellBatch.id}/sell`, { quantity: 1 });
              toast(`${sellBatch.product_name} — 1 adet satıldı`);
            } catch (e) {
              toast(errorMessage(e));
            }
            setSellBatch(null);
            setReload((n) => n + 1);
          }}
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

// Satis onay metni: her zaman tam 1 adet dusulur.
function sellMessage(b) {
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
