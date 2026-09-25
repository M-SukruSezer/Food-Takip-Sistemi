import { useCallback, useEffect, useState } from 'react';
import { Snowflake, Search, TriangleAlert } from 'lucide-react';
import api from '../api';
import { fmtDate, fmtMoney, normalizeSearch } from '../format';

// Stok Yeterliligi: urun urun donuk depo stogu ve satis hizina gore kac gun
// yetecegi. Ana sayfada cok yer kapladigi icin kendi modulu.

const RISK = {
  0: { cls: 'danger', label: 'Stok yok' },
  1: { cls: 'danger', label: 'Kritik' },
  2: { cls: 'warning', label: 'Azalıyor' },
  3: { cls: 'ok', label: 'Yeterli' },
};

function coverText(days) {
  if (days === null || days === undefined) return '-';
  if (days < 1) return 'bugün biter';
  return `${Number(days).toFixed(days < 10 ? 1 : 0)} gün`;
}

export default function StockCoverage() {
  const [stock, setStock] = useState(null);
  const [windowDays, setWindowDays] = useState(14);
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');

  const load = useCallback(() => {
    api.get(`/manager-overview?days=${windowDays}`)
      .then((r) => { setStock(r.data.stock); setError(''); })
      .catch(() => setError('Veri alınamadı'));
  }, [windowDays]);

  useEffect(() => { load(); }, [load]);

  const q = normalizeSearch(query);
  const items = !stock ? [] : q
    ? stock.items.filter((i) => normalizeSearch(i.name).includes(q))
    : stock.items;
  const active = items.filter((i) => i.days_of_cover !== null);
  const idle = items.filter((i) => i.days_of_cover === null);
  const critical = stock ? stock.items.filter((i) => i.risk === 0 || i.risk === 1).length : 0;

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Snowflake size={20} /> Stok Yeterliliği</h2>
      </div>

      {critical > 0 && (
        <div className="alert error" style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ display: 'inline-flex' }}><TriangleAlert size={22} /></span>
          <span style={{ flex: 1 }}>
            <strong>{critical} çeşidin</strong> donuk deposu 3 günden az yetecek veya tükendi.
            Sipariş verilmesi gerekebilir.
          </span>
        </div>
      )}

      <div className="surface-panel">
        <h3 style={{ margin: '0 0 8px', fontSize: 14 }}>Satış hızı penceresi</h3>
        <div className="chip-row" style={{ marginBottom: 10 }}>
          {[7, 14, 30].map((d) => (
            <button
              key={d}
              type="button"
              className={`chip ${windowDays === d ? 'chip-on' : ''}`}
              onClick={() => setWindowDays(d)}
            >
              {d} gün
            </button>
          ))}
        </div>
        <p className="muted" style={{ fontSize: 12, margin: '0 0 12px' }}>
          Son {stock ? stock.window_days : windowDays} günün satış adedinden günlük hız
          bulunur, donuk depodaki adet buna bölünür.
        </p>
        <div className="search-field">
          <Search size={16} />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Ürün ara..."
          />
          {query && (
            <button type="button" className="btn btn-sm btn-secondary" onClick={() => setQuery('')}>
              Temizle
            </button>
          )}
        </div>
      </div>

      {error && <div className="alert error">{error}</div>}

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr>
                <th>Ürün</th><th>Donuk depo</th><th>Çözülen</th><th>Food dolabı</th>
                <th>Satış</th><th>Hız/gün</th><th>Yeterlilik</th><th>Biteceği gün</th>
              </tr>
            </thead>
            <tbody>
              {active.length === 0 && (
                <tr><td data-label="" colSpan="8">
                  <p className="empty">
                    {stock && stock.items.length === 0
                      ? 'Bu mağazada aktif stok veya satış kaydı yok.'
                      : 'Aramaya uyan, satış hareketi olan çeşit yok.'}
                  </p>
                </td></tr>
              )}
              {active.map((i) => {
                const r = RISK[i.risk] || RISK[3];
                return (
                  <tr key={i.product_type_id}>
                    <td data-label="Ürün">
                      <span className={`mo-dot ${r.cls}`} />
                      <strong>{i.name}</strong>
                      <span className={`pill ${r.cls}`} style={{ marginLeft: 8 }}>{r.label}</span>
                    </td>
                    <td data-label="Donuk depo"><strong>{i.frozen_qty}</strong></td>
                    <td data-label="Çözülen">{i.thawing_qty}</td>
                    <td data-label="Food dolabı">{i.cabinet_qty}</td>
                    <td data-label="Satış">{i.sold_qty}</td>
                    <td data-label="Hız/gün">{Number(i.daily_velocity).toFixed(2)}</td>
                    <td data-label="Yeterlilik">
                      <strong className={`text-${r.cls}`}>{coverText(i.days_of_cover)}</strong>
                    </td>
                    <td data-label="Biteceği gün">
                      {i.depletion_date ? fmtDate(i.depletion_date) : '-'}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {idle.length > 0 && (
        <div className="surface-panel">
          <h3 style={{ margin: '0 0 4px', fontSize: 14 }}>
            Satış hareketi olmayan {idle.length} çeşit
          </h3>
          <p className="muted" style={{ fontSize: 12, margin: '0 0 10px' }}>
            Satış hızı sıfır olduğu için yeterlilik hesaplanamaz.
          </p>
          <div className="chip-row">
            {idle.map((i) => (
              <span className="chip" key={i.product_type_id}>
                {i.name} · {i.frozen_qty} adet
                {i.frozen_value != null && ` · ${fmtMoney(i.frozen_value)}`}
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
