import { useEffect, useState, useCallback, useMemo } from 'react';
import { Link } from 'react-router-dom';
import {
  Flame, PartyPopper, TriangleAlert, Snowflake, Hourglass, Refrigerator, Banknote, ShoppingBag,
  Clock, ClipboardCheck, Trash2, Store, TrendingUp, Activity, ArrowUpRight, ArrowDownRight,
  ChartColumn, ChevronDown, ChevronUp,
} from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Confirm, Modal, StatusBadge, toast } from '../components/ui';
import { fmtDate, fmtDateTime, formatHours, errorMessage, fmtMoney, hasPrice, isUrgentBatch, sumRemaining } from '../format';

const STATUS_CHART_LABELS = {
  frozen: 'Donuk Depo',
  thawing: 'Çözülme',
  food_cabinet: 'Food Dolabı',
  sold: 'Satıldı',
  discarded: 'İmha',
};

const STATUS_CHART_TONE = {
  frozen: 'frozen',
  thawing: 'thawing',
  food_cabinet: 'cabinet',
  sold: 'sold',
  discarded: 'discarded',
};

export default function Dashboard() {
  const { user } = useAuth();
  const isSuper = user.role === 'super_admin';

  const [data, setData] = useState(null);
  const [recs, setRecs] = useState([]);
  const [pendingApprovals, setPendingApprovals] = useState(0);
  const [sellBatch, setSellBatch] = useState(null);
  const [discardBatch, setDiscardBatch] = useState(null);
  const [reload, setReload] = useState(0);

  // rapor verileri
  const [summary, setSummary] = useState(null);
  const [chart, setChart] = useState([]);
  const [statusChart, setStatusChart] = useState([]);
  const [storeId, setStoreId] = useState('');
  const [stores, setStores] = useState([]);
  const [showReports, setShowReports] = useState(
    () => typeof window === 'undefined' || window.matchMedia('(min-width: 900px)').matches
  );

  const load = useCallback(() => {
    const q = storeId ? `?storeId=${storeId}` : '';
    api.get('/dashboard' + q).then((r) => setData(r.data)).catch(() => {});
    api.get('/recommendations' + q).then((r) => setRecs(r.data)).catch(() => {});
    api.get('/reports/summary' + q).then((r) => setSummary(r.data)).catch(() => {});
    api.get('/reports/sales7' + q).then((r) => setChart(r.data)).catch(() => {});
    api.get('/reports/status' + q).then((r) => setStatusChart(r.data)).catch(() => {});
    if (['super_admin', 'store_manager'].includes(user.role)) {
      api.get('/approvals?status=pending').then((r) => setPendingApprovals(r.data.length)).catch(() => {});
    }
  }, [user.role, storeId]);

  useEffect(() => { load(); }, [load, reload]);

  useEffect(() => {
    const t = setInterval(load, 60000);
    return () => clearInterval(t);
  }, [load]);

  useEffect(() => {
    if (isSuper) api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [isSuper]);

  const refresh = () => setReload((n) => n + 1);

  // SKT'ye 48 saatten az kalanlar; food dolabındaki geri kalan stok öneri listesinde.
  const urgent = useMemo(() => recs.filter(isUrgentBatch), [recs]);

  const derived = useMemo(() => {
    const maxQty = Math.max(1, ...chart.map((d) => d.qty));
    const maxRevenue = Math.max(1, ...chart.map((d) => d.revenue));
    const maxStatus = Math.max(1, ...statusChart.map((d) => d.quantity));
    const firstHalf = chart.slice(0, Math.ceil(chart.length / 2)).reduce((sum, d) => sum + d.revenue, 0);
    const secondHalf = chart.slice(Math.ceil(chart.length / 2)).reduce((sum, d) => sum + d.revenue, 0);
    const trend = firstHalf > 0
      ? Math.round(((secondHalf - firstHalf) / firstHalf) * 100)
      : (secondHalf > 0 ? 100 : 0);
    const totalRevenue = !summary
      ? 0
      : summary.type === 'multi'
        ? summary.stores.reduce((sum, s) => sum + Number(s.revenue || 0), 0)
        : Number(summary.revenue || 0);
    const sold7 = chart.reduce((s, d) => s + d.qty, 0);
    return { maxQty, maxRevenue, maxStatus, trend, totalRevenue, sold7 };
  }, [chart, statusChart, summary]);

  if (!data) return <div className="card"><p className="muted">Yükleniyor...</p></div>;

  const c = data.counts;
  const expiredCount = sumRemaining(recs.filter((r) => r.urgency === 'expired'));

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

      {isSuper && (
        <div className="page-head">
          <h2><Store size={20} /> Mağaza Seçimi</h2>
          <select value={storeId} onChange={(e) => setStoreId(e.target.value)}>
            <option value="">Tüm Mağazalar</option>
            {stores.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        </div>
      )}

      <section className="hero-panel">
        <div className="hero-copy">
          <div className="eyebrow">Operasyon Özeti</div>
          <h2>Bugün için en kritik operasyonlar hazır.</h2>
          <p>
            {urgent.length > 0
              ? `${sumRemaining(urgent)} adet ürün, SKT süresi yaklaşan kuyruğa dahil.`
              : 'Acil satış bekleyen ürün bulunmuyor. Operasyon akışı stabil.'}
          </p>
          <div className="hero-actions">
            <Link to="/batches" className="btn btn-primary">Stok Takibi</Link>
            <Link to="/recommendations" className="btn btn-secondary">Öneri Satış Listesi</Link>
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
        <div className="page-head" style={{ marginBottom: urgent.length ? 12 : 0 }}>
          <h2><Flame size={21} /> Öncelikle Satılması Gerekenler</h2>
          <Link to="/recommendations" className="btn btn-sm btn-secondary">Tüm Liste</Link>
        </div>

        {urgent.length === 0 ? (
          <div className="rec-empty">
            <span style={{ display: 'inline-flex' }}><PartyPopper size={30} /></span>
            <div>
              <strong>Acil satış bekleyen ürün yok.</strong>
              <div className="muted">
                Food dolabında SKT'ye 2 günden az kalan ürün bulunmuyor
                {recs.length > 0 ? `; dolapta ${sumRemaining(recs)} adet ürün satışa hazır.` : '.'}
              </div>
            </div>
          </div>
        ) : (
          <>
            <p className="muted" style={{ fontSize: 13, margin: '0 0 10px' }}>
              SKT'ye son 2 gün kalan <strong>{sumRemaining(urgent)} adet</strong> ({urgent.length} kayıt) ürün — en acil en üstte.
            </p>
            <div className="rec-list">
              {urgent.map((b) => (
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

      {summary && (
        <>
          <button
            type="button"
            className="section-toggle"
            aria-expanded={showReports}
            onClick={() => setShowReports((v) => !v)}
          >
            <span><ChartColumn size={18} /> Raporlar</span>
            {showReports ? <ChevronUp size={18} /> : <ChevronDown size={18} />}
          </button>

          {showReports && (
        <div className="analytics-layout">
          <div className="analytics-main">
            {summary.type === 'multi' ? (
              <>
                <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                  <div className="table-wrap">
                    <table>
                      <thead>
                        <tr>
                          <th>Mağaza</th><th>Ürün Çeşidi</th><th>Donuk</th><th>Çözülme</th>
                          <th>Food Dolabı</th><th>Satılan</th><th>Ciro</th><th>İmha</th>
                        </tr>
                      </thead>
                      <tbody>
                        {summary.stores.map((s) => (
                          <tr key={s.id}>
                            <td><strong>{s.name}</strong></td>
                            <td>{s.product_count}</td>
                            <td>{s.frozen_qty}</td>
                            <td>{s.thawing_qty}</td>
                            <td>{s.cabinet_qty}</td>
                            <td>{s.sold_qty} ({s.sold_count} işlem)</td>
                            <td>{s.revenue.toLocaleString('tr-TR')} TL</td>
                            <td>{s.discarded_qty}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
                <p className="muted" style={{ fontSize: 13 }}>Merkezi rapor: Ana yönetici tüm mağazaları buradan karşılaştırabilir.</p>
              </>
            ) : (
              <div className="grid stats kpi-grid">
                <div className="stat stat-card">
                  <div className="label"><span><Store size={15} /> {summary.store?.name}</span></div>
                  <div className="value">{summary.product_count}</div>
                  <div className="sub">aktif ürün çeşidi</div>
                </div>
                <div className="stat stat-card">
                  <div className="label"><span><Banknote size={15} /> Toplam Satış</span></div>
                  <div className="value">{summary.sold_qty} adet</div>
                  <div className="sub">{summary.revenue.toLocaleString('tr-TR')} TL ciro</div>
                </div>
                <div className="stat stat-card">
                  <div className="label"><span><Trash2 size={15} /> İmha</span></div>
                  <div className="value">{summary.discarded_qty}</div>
                  <div className="sub">adet</div>
                </div>
              </div>
            )}

            <div className="card chart-panel">
              <div className="panel-header">
                <div>
                  <div className="panel-kicker">Trend</div>
                  <h3>Son 7 Günlük Satış</h3>
                </div>
                <div className={`panel-trend ${derived.trend >= 0 ? 'up' : 'down'}`}>
                  {derived.trend >= 0 ? <TrendingUp size={16} /> : <ArrowDownRight size={16} />} {derived.trend > 0 ? '+' : ''}{derived.trend}%
                </div>
              </div>

              <div className="chart-stack">
                <div className="chart-block">
                  <div className="muted chart-label">Satış Adedi</div>
                  <div className="bar-chart">
                    {chart.map((d) => (
                      <div key={d.date} className="bar-col">
                        <span className="bar-value">{d.qty}</span>
                        <div className="bar" style={{ height: `${Math.max(14, (d.qty / derived.maxQty) * 100)}%` }} />
                        <span className="bar-date">{fmtDate(d.date).slice(0, 5)}</span>
                      </div>
                    ))}
                  </div>
                </div>

                <div className="chart-block">
                  <div className="muted chart-label">Ciro (TL)</div>
                  <div className="bar-chart revenue">
                    {chart.map((d) => (
                      <div key={d.date} className="bar-col">
                        <span className="bar-value">{Math.round(d.revenue)}</span>
                        <div className="bar revenue" style={{ height: `${Math.max(14, (d.revenue / derived.maxRevenue) * 100)}%` }} />
                        <span className="bar-date">{fmtDate(d.date).slice(0, 5)}</span>
                      </div>
                    ))}
                  </div>
                </div>

                <div className="chart-block">
                  <div className="muted chart-label">Stok Dağılımı</div>
                  <div className="status-chart">
                    {statusChart.length === 0 && <p className="empty">Stok verisi bulunamadı</p>}
                    {statusChart.map((item) => (
                      <div className="status-bar-row" key={item.status}>
                        <span>{STATUS_CHART_LABELS[item.status] || item.status}</span>
                        <div className="status-bar-track">
                          <div className={`status-bar ${STATUS_CHART_TONE[item.status] || ''}`} style={{ width: `${Math.max(4, (item.quantity / derived.maxStatus) * 100)}%` }} />
                        </div>
                        <strong>{item.quantity}</strong>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <aside className="analytics-sidebar">
            <div className="mini-panel dark-card">
              <div className="panel-header compact">
                <div>
                  <div className="panel-kicker">Snapshot</div>
                  <h3>Operasyon</h3>
                </div>
                <Activity size={18} />
              </div>
              <div className="sidebar-metric">
                <span>Toplam Ciro</span>
                <strong>{derived.totalRevenue.toLocaleString('tr-TR')} TL</strong>
              </div>
              <div className="sidebar-metric">
                <span>Son 7 Gün Satış</span>
                <strong>{derived.sold7} adet</strong>
              </div>
              <div className="sidebar-metric">
                <span>Ortalama Günlük</span>
                <strong>{Math.round(derived.sold7 / Math.max(chart.length, 1))} adet</strong>
              </div>
            </div>

            <div className="mini-panel dark-card">
              <div className="panel-header compact">
                <div>
                  <div className="panel-kicker">Trend</div>
                  <h3>Hızlı Durum</h3>
                </div>
                <TrendingUp size={18} />
              </div>
              <div className="trend-list">
                <div className="trend-row up">
                  <span className="trend-icon"><ArrowUpRight size={14} /></span>
                  <div>
                    <strong>Satış</strong>
                    <small>{derived.trend > 0 ? '+' : ''}{derived.trend}% son 7 gün</small>
                  </div>
                </div>
                <div className="trend-row down">
                  <span className="trend-icon"><ArrowDownRight size={14} /></span>
                  <div>
                    <strong>Stok</strong>
                    <small>{statusChart.reduce((sum, item) => sum + item.quantity, 0)} adet toplam</small>
                  </div>
                </div>
              </div>
            </div>

          </aside>
        </div>
          )}
        </>
      )}

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
        {hasPrice(batch.product_unit_price) ? (
          <div className="field">
            <label>Tutar</label>
            <p style={{ margin: 0 }}>
              {fmtMoney(batch.product_unit_price)} × {Number(quantity) || 0} adet ={' '}
              <strong>{fmtMoney((Number(batch.product_unit_price) || 0) * (Number(quantity) || 0))}</strong>
            </p>
            <small className="muted">Birim fiyat pasta çeşidinde tanımlıdır, ciro otomatik hesaplanır.</small>
          </div>
        ) : (
          <div className="alert warning">
            Bu çeşit için satış fiyatı tanımlı değil; ciroya 0 TL yazılacak. Pasta Çeşitleri ekranından fiyat tanımlayabilirsiniz.
          </div>
        )}
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-success">Satışı Kaydet</button>
        </div>
      </form>
    </Modal>
  );
}
