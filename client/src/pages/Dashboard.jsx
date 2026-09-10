import { useEffect, useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { Flame, PartyPopper, TriangleAlert, Snowflake, Hourglass, Refrigerator, Banknote, ShoppingBag, Clock, ClipboardCheck, Trash2 } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Confirm, Modal, StatusBadge, toast } from '../components/ui';
import { fmtDateTime, formatHours, errorMessage } from '../format';

export default function Dashboard() {
  const { user } = useAuth();
  const [data, setData] = useState(null);
  const [recs, setRecs] = useState([]);
  const [pendingApprovals, setPendingApprovals] = useState(0);
  const [sellBatch, setSellBatch] = useState(null);
  const [discardBatch, setDiscardBatch] = useState(null);
  const [reload, setReload] = useState(0);

  const load = useCallback(() => {
    api.get('/dashboard').then((r) => setData(r.data)).catch(() => {});
    api.get('/recommendations').then((r) => setRecs(r.data)).catch(() => {});
    if (user && ['super_admin', 'store_manager'].includes(user.role)) {
      api.get('/approvals?status=pending').then((r) => setPendingApprovals(r.data.length)).catch(() => {});
    }
  }, [user]);

  useEffect(() => {
    load();
  }, [load, reload]);

  useEffect(() => {
    const t = setInterval(load, 60000);
    return () => clearInterval(t);
  }, [load]);

  const refresh = () => setReload((n) => n + 1);

  if (!data) return <div className="card"><p className="muted">Yükleniyor...</p></div>;

  const c = data.counts;
  const expiredCount = recs.filter((r) => r.urgency === 'expired').reduce((s, r) => s + r.remaining, 0);

  return (
    <div className="dashboard-shell">
      {expiredCount > 0 && (
        <div className="alert error" style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
          <span style={{ display: 'inline-flex' }}><TriangleAlert size={22} /></span>
          <span style={{ flex: 1 }}>
            <strong>{expiredCount} adet</strong> ürünün SKT'si doldu! Satışa sunulmamalı, hemen imha edilmeli.
          </span>
        </div>
      )}

      {pendingApprovals > 0 && (
        <div className="alert warning" style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
          <span style={{ display: 'inline-flex' }}><ClipboardCheck size={22} /></span>
          <span style={{ flex: 1 }}>
            <strong>{pendingApprovals} erken aktarım isteği</strong> onayını bekliyor.
          </span>
          <Link to="/approvals" className="btn btn-sm btn-primary">İncele</Link>
        </div>
      )}

      <section className="hero-panel">
        <div className="hero-copy">
          <div className="eyebrow">Operasyon Özeti</div>
          <h2>Bugün için en kritik operasyonlar hazır.</h2>
          <p>
            {recs.length > 0
              ? `${recs.reduce((s, r) => s + r.remaining, 0)} adet ürün, SKT süresi yaklaşan kuyruğa dahil.`
              : 'Acil satış bekleyen ürün bulunmuyor. Operasyon akışı stabil.'}
          </p>
          <div className="hero-actions">
            <Link to="/batches" className="btn btn-primary">Stok Takibi</Link>
            <Link to="/reports" className="btn btn-secondary">Raporlar</Link>
          </div>
        </div>

        <div className="hero-metrics">
          <div className="mini-kpi success">
            <span className="mini-label">Toplam Stok</span>
            <strong>{(c.frozen_qty || 0) + (c.thawing_qty || 0) + (c.food_cabinet_qty || 0)}</strong>
            <small>adet</small>
          </div>
          <div className="mini-kpi warning">
            <span className="mini-label">Bugün Ciro</span>
            <strong>{(data.soldToday.revenue || 0).toLocaleString('tr-TR')}</strong>
            <small>TL</small>
          </div>
          <div className="mini-kpi danger">
            <span className="mini-label">Acil Durum</span>
            <strong>{expiredCount}</strong>
            <small>adet</small>
          </div>
        </div>
      </section>

      <div className="card rec-hero">
        <div className="page-head" style={{ marginBottom: recs.length ? 12 : 0 }}>
          <h2><Flame size={21} /> Öncelikle Satılması Gerekenler</h2>
        </div>

        {recs.length === 0 ? (
          <div className="rec-empty">
            <span style={{ display: 'inline-flex' }}><PartyPopper size={30} /></span>
            <div><strong>Acil satış bekleyen ürün yok.</strong><div className="muted">Food dolabında SKT'ye 2 günden az kalan ürün bulunmuyor.</div></div>
          </div>
        ) : (
          <>
            <p className="muted" style={{ fontSize: 13, margin: '0 0 10px' }}>
              SKT'ye son 2 gün kalan <strong>{recs.reduce((s, r) => s + r.remaining, 0)} adet</strong> ({recs.length} kayıt) ürün — en acil en üstte.
            </p>
            <div className="rec-list">
              {recs.map((b) => (
                <div key={b.id} className={`rec-card ${b.urgency}`}>
                  <div className="info">
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                      <strong style={{ fontSize: 16 }}>{b.product_name}</strong>
                      <StatusBadge status={b.status} urgency={b.urgency} />
                    </div>
                    <div className="muted" style={{ fontSize: 13 }}>
                      SKT: {fmtDateTime(b.skt_end)}
                    </div>
                    <div className="rec-countdown">
                      <Clock size={14} /> {b.urgency === 'expired' ? 'Süre doldu' : `${formatHours(b.remaining_hours)} kaldı`}
                    </div>
                  </div>
                  <div className="rec-side">
                    <div className="qty">{b.remaining}<span> adet</span></div>
                    <div className="rec-actions">
                      {b.urgency !== 'expired' ? (
                        <button className="btn btn-success" onClick={() => setSellBatch(b)}><Banknote size={17} /> Sat</button>
                      ) : (
                        <button className="btn btn-danger" onClick={() => setDiscardBatch(b)}><Trash2 size={17} /> İmha</button>
                      )}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </div>

      <div className="grid stats kpi-grid">
        <Stat icon={Snowflake} label="Donuk Depo" value={c.frozen_qty} sub={`${c.frozen} kayıt`} color="var(--info)" />
        <Stat icon={Hourglass} label="Çözülme" value={c.thawing_qty} sub={`${c.thawing} kayıt`} color="var(--warning)" />
        <Stat icon={Refrigerator} label="Food Dolabı" value={c.food_cabinet_qty} sub={`${c.food_cabinet} kayıt`} color="var(--success)" />
        <Stat icon={TriangleAlert} label="SKT Geçen" value={c.expired_qty} sub="imha edilmeli" color="var(--danger)" />
      </div>

      <div className="grid stats kpi-grid" style={{ marginTop: 12 }}>
        <Stat icon={Banknote} label="Bugün Satılan" value={`${data.soldToday.qty} adet`} sub={`${(data.soldToday.revenue || 0).toLocaleString('tr-TR')} TL ciro`} />
        <Stat icon={ShoppingBag} label="Bugünkü İşlem" value={data.soldToday.count} sub="satış kaydı" />
      </div>

      {sellBatch && (
        <QuickSellModal
          batch={sellBatch}
          onClose={() => setSellBatch(null)}
          onDone={() => { setSellBatch(null); refresh(); }}
        />
      )}

      {discardBatch && (
        <Confirm
          title="İmha Et"
          message={`${discardBatch.product_name} (${discardBatch.remaining} adet) SKT'si dolduğu için imha edilecek. Onaylıyor musunuz?`}
          confirmLabel="İmha Et"
          onCancel={() => setDiscardBatch(null)}
          onConfirm={async () => {
            try {
              await api.post(`/batches/${discardBatch.id}/discard`, { reason: 'SKT süresi doldu' });
              toast('Ürün imha edildi');
            } catch (e) {
              toast(errorMessage(e));
            }
            setDiscardBatch(null);
            refresh();
          }}
        />
      )}
    </div>
  );
}

function Stat({ icon: Icon, label, value, sub, color }) {
  return (
    <div className="stat stat-card">
      <div className="label"><span>{Icon && <Icon size={15} />} {label}</span></div>
      <div className="value" style={color ? { color } : undefined}>{value}</div>
      <div className="sub">{sub}</div>
    </div>
  );
}

function QuickSellModal({ batch, onClose, onDone }) {
  const [quantity, setQuantity] = useState(batch.remaining);
  const [unit_price, setUnitPrice] = useState('');
  const [err, setErr] = useState('');
  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      await api.post(`/batches/${batch.id}/sell`, { quantity, unit_price });
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
        <div className="field">
          <label>Birim Fiyat (TL, opsiyonel)</label>
          <input type="number" min="0" step="0.01" value={unit_price} onChange={(e) => setUnitPrice(e.target.value)} placeholder="0,00" />
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-success">Satışı Kaydet</button>
        </div>
      </form>
    </Modal>
  );
}
