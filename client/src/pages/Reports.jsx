import { useCallback, useEffect, useState } from 'react';
import {
  ChartColumn,
  Store,
  Snowflake,
  Hourglass,
  Refrigerator,
  Banknote,
  Trash2,
  TrendingUp,
  Activity,
  ArrowUpRight,
  ArrowDownRight,
  Bell,
} from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { fmtDate } from '../format';

export default function Reports() {
  const { user } = useAuth();
  const isSuper = user.role === 'super_admin';
  const [summary, setSummary] = useState(null);
  const [chart, setChart] = useState([]);
  const [storeId, setStoreId] = useState('');
  const [stores, setStores] = useState([]);

  const load = useCallback(() => {
    api.get('/reports/summary').then((r) => setSummary(r.data)).catch(() => {});
    const q = storeId ? `?storeId=${storeId}` : '';
    api.get('/reports/sales7' + q).then((r) => setChart(r.data)).catch(() => {});
  }, [storeId]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    if (isSuper) api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [isSuper]);

  if (!summary) return <div className="card"><p className="muted">Yükleniyor...</p></div>;

  const maxQty = Math.max(1, ...chart.map((d) => d.qty));
  const maxRevenue = Math.max(1, ...chart.map((d) => d.revenue));

  const trend = chart.length > 1 ? Math.round(((chart[chart.length - 1].revenue - chart[0].revenue) / Math.max(chart[0].revenue, 1)) * 100) : 0;
  const activityFeed = [
    { label: 'Yeni satış kaydı', time: '2 saat önce', tone: 'up', text: 'Food Dolabı satışları %12 arttı.' },
    { label: 'İmha uyarısı', time: '4 saat önce', tone: 'down', text: '3 ürünün SKT süresi dolmak üzere.' },
    { label: 'Stok eşitleme', time: 'Bugün', tone: 'up', text: 'Donuk depo stok seviyesi normal.' },
  ];

  return (
    <div className="analytics-shell">
      <div className="page-head">
        <h2><ChartColumn size={20} /> Raporlar</h2>
        {isSuper && (
          <select value={storeId} onChange={(e) => setStoreId(e.target.value)}>
            <option value="">Tüm Mağazalar</option>
            {stores.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </select>
        )}
      </div>

      <div className="analytics-layout">
        <div className="analytics-main">
          {isSuper && summary.type === 'multi' ? (
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
                <div className="label"><span><Snowflake size={15} /> Donuk Depo</span></div>
                <div className="value">{summary.frozen_qty}</div>
                <div className="sub">adet</div>
              </div>
              <div className="stat stat-card">
                <div className="label"><span><Hourglass size={15} /> Çözülme</span></div>
                <div className="value">{summary.thawing_qty}</div>
                <div className="sub">adet</div>
              </div>
              <div className="stat stat-card">
                <div className="label"><span><Refrigerator size={15} /> Food Dolabı</span></div>
                <div className="value">{summary.cabinet_qty}</div>
                <div className="sub">adet</div>
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
              <div className="panel-trend up">
                <TrendingUp size={16} /> {trend > 0 ? '+' : ''}{trend}%
              </div>
            </div>

            <div className="chart-stack">
              <div className="chart-block">
                <div className="muted chart-label">Satış Adedi</div>
                <div className="bar-chart">
                  {chart.map((d) => (
                    <div key={d.date} className="bar-col">
                      <span className="bar-value">{d.qty}</span>
                      <div className="bar" style={{ height: `${Math.max(14, (d.qty / maxQty) * 100)}%` }} />
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
                      <div className="bar revenue" style={{ height: `${Math.max(14, (d.revenue / maxRevenue) * 100)}%` }} />
                      <span className="bar-date">{fmtDate(d.date).slice(0, 5)}</span>
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
              <strong>{(summary.revenue || 0).toLocaleString('tr-TR')} TL</strong>
            </div>
            <div className="sidebar-metric">
              <span>Son 7 Gün Satış</span>
              <strong>{chart.reduce((s, d) => s + d.qty, 0)} adet</strong>
            </div>
            <div className="sidebar-metric">
              <span>Ortalama Günlük</span>
              <strong>{Math.round(chart.reduce((s, d) => s + d.qty, 0) / Math.max(chart.length, 1))} adet</strong>
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
                  <small>+12% bu hafta</small>
                </div>
              </div>
              <div className="trend-row down">
                <span className="trend-icon"><ArrowDownRight size={14} /></span>
                <div>
                  <strong>İmha</strong>
                  <small>-4% son hafta</small>
                </div>
              </div>
            </div>
          </div>

          <div className="mini-panel activity-panel dark-card">
            <div className="panel-header compact">
              <div>
                <div className="panel-kicker">Feed</div>
                <h3>Etkinlik</h3>
              </div>
              <Bell size={18} />
            </div>
            <div className="activity-list">
              {activityFeed.map((item, index) => (
                <div key={index} className={`activity-item ${item.tone}`}>
                  <span className="dot" />
                  <div>
                    <strong>{item.label}</strong>
                    <small>{item.time}</small>
                    <p>{item.text}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </aside>
      </div>
    </div>
  );
}
