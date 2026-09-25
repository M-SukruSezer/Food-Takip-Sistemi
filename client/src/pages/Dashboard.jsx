import { useEffect, useState, useCallback, useMemo } from 'react';
import { Link } from 'react-router-dom';
import {
  TriangleAlert, Snowflake, Hourglass, Refrigerator, Banknote, ShoppingBag,
  ClipboardCheck, Trash2, Store, TrendingUp, Activity, ArrowUpRight, ArrowDownRight, Award, TrendingDown,
} from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { fmtDate, REPORT_PANEL_ROLES } from '../format';
import ManagerOverview from '../components/ManagerOverview';

const STATUS_CHART_LABELS = {
  frozen: 'Donuk Depo',
  thawing: 'Çözülme',
  food_cabinet: 'Food Dolabı',
  sold: 'Satıldı',
  ikram: 'İkram',
  discarded: 'Zayi',
};

const STATUS_CHART_TONE = {
  frozen: 'frozen',
  thawing: 'thawing',
  food_cabinet: 'cabinet',
  sold: 'sold',
  ikram: 'warning',
  discarded: 'discarded',
};

export default function Dashboard() {
  const { user } = useAuth();
  const isSuper = user.role === 'super_admin';

  const [data, setData] = useState(null);
  const [pendingApprovals, setPendingApprovals] = useState(0);
  const [reload, setReload] = useState(0);
  const [loadError, setLoadError] = useState(false);

  // rapor verileri
  const [summary, setSummary] = useState(null);
  const [chart, setChart] = useState([]);
  const [statusChart, setStatusChart] = useState([]);
  const [products, setProducts] = useState(null);
  const [period, setPeriod] = useState('week');
  const [storeId, setStoreId] = useState('');
  const [stores, setStores] = useState([]);
  // Ana sayfadaki genel rapor: yalnizca magaza muduru ve vardiya muduru.
  const showOverview = REPORT_PANEL_ROLES.includes(user.role);
  const [overview, setOverview] = useState(null);
  const [reportFields, setReportFields] = useState({ entry: [], system: [], derived: [] });
  // silent: 60 saniyelik otomatik yenileme kullanicinin basladigi bir islem
  // degil; ekrani her dakika kilitlememesi icin katman ve bildirim olmadan doner.
  const load = useCallback((silent = false) => {
    const q = storeId ? `?storeId=${storeId}` : '';
    const opts = { silent };
    api.get('/dashboard' + q, opts)
      .then((r) => { setData(r.data); setLoadError(false); })
      .catch(() => setLoadError(true));
    api.get('/reports/summary' + q, opts).then((r) => setSummary(r.data)).catch(() => {});
    api.get('/reports/sales7' + q, opts).then((r) => setChart(r.data)).catch(() => {});
    api.get('/reports/status' + q, opts).then((r) => setStatusChart(r.data)).catch(() => {});
    api.get('/reports/products' + q, opts).then((r) => setProducts(r.data)).catch(() => {});
    if (['super_admin', 'store_manager'].includes(user.role)) {
      api.get('/approvals?status=pending', opts).then((r) => setPendingApprovals(r.data.length)).catch(() => {});
    }
    // Genel rapor ayri alinir: hata verirse ana sayfanin geri kalani gorunur kalsin.
    if (REPORT_PANEL_ROLES.includes(user.role)) {
      api.get('/manager-overview' + (storeId ? `?storeId=${storeId}` : ''), { silent: true })
        .then((r) => setOverview(r.data))
        .catch(() => {});
    }
  }, [user.role, storeId]);

  useEffect(() => { load(); }, [load, reload]);

  useEffect(() => {
    if (!showOverview) return;
    api.get('/daily-reports/fields', { silent: true })
      .then((r) => setReportFields({ entry: [], system: [], derived: [], ...r.data }))
      .catch(() => {});
  }, [showOverview]);

  useEffect(() => {
    const t = setInterval(() => load(true), 60000);
    return () => clearInterval(t);
  }, [load]);

  useEffect(() => {
    if (isSuper) api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [isSuper]);

  const refresh = () => setReload((n) => n + 1);

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

  const perf = useMemo(() => {
    const p = products && products[period];
    if (!p) return null;
    const sold = p.sold || [];
    const wasted = p.wasted || [];
    const sum = (list) => list.reduce((a, x) => a + Number(x.qty || 0), 0);
    return {
      best: sold.slice(0, 5),
      // sold zaten azalan sirada; tersleyip ilk 5 en az satanlari verir
      worst: sold.slice().reverse().slice(0, 5),
      wasted: wasted.slice(0, 5),
      soldTotal: sum(sold),
      wastedTotal: sum(wasted),
      kinds: sold.length,
    };
  }, [products, period]);

  if (!data) {
    // Engelleyici katmanin kalici kilide donusmemesi icin hatada cikis yolu birakilir.
    if (loadError) {
      return (
        <div className="card">
          <div className="alert error">Veriler yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.</div>
          <button className="btn btn-primary" onClick={() => { setLoadError(false); refresh(); }}>Tekrar Dene</button>
        </div>
      );
    }
    // Yukleme katmanini global BusyHost gosterir.
    return null;
  }

  const c = data.counts;
  const expiredCount = c.expired_qty || 0;

  return (
    <div className="dashboard-shell">
      {/* Ciro Forecast ve Petty Cash en ustte: magaza muduru ve vardiya
          muduru gune bu iki rakamla basliyor. */}
      {showOverview && overview && (
        <ManagerOverview overview={overview} fields={reportFields} />
      )}

      {expiredCount > 0 && (
        <div className="alert error" style={{ display: 'flex', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
          <span style={{ display: 'inline-flex' }}><TriangleAlert size={22} /></span>
          <span style={{ flex: 1 }}>
            <strong>{expiredCount} adet</strong> ürünün SKT'si doldu! Satışa sunulmamalı, hemen zayi verilmeli.
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
          <h2>Bugün için en kritik operasyonlar hazır.</h2>
          <p>
            {c.expiring_count > 0
              ? `${c.expiring_qty || 0} adet ürün son 24 saatte, ${c.expiring_count} kayıt SKT kuyruğunda.`
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

      <div className="grid stats kpi-grid">
        <Stat icon={Snowflake} label="Donuk Depo" value={c.frozen_qty} sub={`${c.frozen} kayıt`} color="var(--info)" to="/batches?tab=frozen" />
        <Stat icon={Hourglass} label="Çözülme" value={c.thawing_qty} sub={`${c.thawing} kayıt`} color="var(--warning)" to="/batches?tab=thawing" />
        <Stat icon={Refrigerator} label="Food Dolabı" value={c.food_cabinet_qty} sub={`${c.food_cabinet} kayıt`} color="var(--success)" to="/batches?tab=food_cabinet" />
        <Stat icon={TriangleAlert} label="SKT Geçen" value={c.expired_qty} sub="zayi verilmeli" color="var(--danger)" to="/recommendations" />
        <Stat icon={Banknote} label="Bugün Satılan" value={`${data.soldToday.qty} adet`} sub={`${(data.soldToday.revenue || 0).toLocaleString('tr-TR')} TL ciro`} to="/sales?range=today&kind=sale" />
        <Stat icon={ShoppingBag} label="Bugünkü İşlem" value={data.soldToday.count} sub="satış kaydı" to="/sales?range=today" />
      </div>


      {summary && (
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
                          <th>Food Dolabı</th><th>Satılan</th><th>Ciro</th><th>Zayi</th>
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
                <Link to="/sales?kind=sale" className="stat stat-card stat-link">
                  <div className="label"><span><Banknote size={15} /> Toplam Satış</span></div>
                  <div className="value">{summary.sold_qty} adet</div>
                  <div className="sub">{summary.revenue.toLocaleString('tr-TR')} TL ciro</div>
                </Link>
                <Link to="/sales?kind=discard" className="stat stat-card stat-link">
                  <div className="label"><span><Trash2 size={15} /> Zayi</span></div>
                  <div className="value">{summary.discarded_qty}</div>
                  <div className="sub">adet</div>
                </Link>
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
                  <div className="muted chart-label">Durum Dağılımı</div>
                  <div className="status-chart">
                    {statusChart.length === 0 && <p className="empty">Veri bulunamadı</p>}
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

            {products && perf && (
              <div className="card chart-panel">
                <div className="panel-header">
                  <div>
                    <div className="panel-kicker">Ürün Performansı</div>
                    <h3>{period === 'week' ? 'Son 7 Gün' : 'Son 30 Gün'}</h3>
                  </div>
                  <div className="tabs period-tabs">
                    <button
                      type="button"
                      className={period === 'week' ? 'active' : ''}
                      onClick={() => setPeriod('week')}
                    >Hafta</button>
                    <button
                      type="button"
                      className={period === 'month' ? 'active' : ''}
                      onClick={() => setPeriod('month')}
                    >Ay</button>
                  </div>
                </div>

                <div className="rank-grid">
                  <RankList title="En Çok Satan" icon={Award} tone="up" rows={perf.best} empty="Bu dönemde satış yok" />
                  <RankList title="En Az Satan" icon={TrendingDown} tone="down" rows={perf.worst} empty="Bu dönemde satış yok" />
                  <RankList title="En Çok Zayi" icon={Trash2} tone="waste" rows={perf.wasted} empty="Bu dönemde zayi yok" />
                </div>

                <p className="muted" style={{ fontSize: 12, margin: '12px 0 0' }}>
                  Dönemde {perf.kinds} çeşitten toplam {perf.soldTotal} adet satıldı, {perf.wastedTotal} adet zayi verildi.
                  {perf.kinds > 0 && perf.kinds <= 5
                    ? ' Satılan çeşit sayısı 5 veya altında olduğu için en çok ve en az satan listeleri aynı ürünleri içerir.'
                    : ''}
                </p>
              </div>
            )}
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

    </div>
  );
}

function RankList({ title, icon: Icon, rows, tone, empty }) {
  const max = Math.max(1, ...rows.map((r) => Number(r.qty) || 0));
  return (
    <div className="rank-block">
      <div className="rank-head">{Icon && <Icon size={15} />} {title}</div>
      {rows.length === 0 ? (
        <p className="empty">{empty}</p>
      ) : (
        <ol className="rank-list">
          {rows.map((r) => (
            <li key={r.id}>
              <span className="rank-name" title={r.name}>{r.name}</span>
              <span className="rank-bar-track">
                <span
                  className={`rank-bar ${tone}`}
                  style={{ width: `${Math.max(6, (Number(r.qty) / max) * 100)}%` }}
                />
              </span>
              <strong className="rank-qty">{r.qty}</strong>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

// to verilirse kutu tiklanabilir olur ve ilgili ekrani acar.
function Stat({ icon: Icon, label, value, sub, color, to }) {
  const inner = (
    <>
      <div className="label"><span>{Icon && <Icon size={15} />} {label}</span></div>
      <div className="value" style={color ? { color } : undefined}>{value}</div>
      <div className="sub">{sub}</div>
    </>
  );
  if (!to) return <div className="stat stat-card">{inner}</div>;
  return <Link to={to} className="stat stat-card stat-link">{inner}</Link>;
}
