import { Sparkles, TrendingUp, Wallet, Snowflake } from 'lucide-react';
import { fmtDate, fmtMoney } from '../format';

// Ana sayfadaki genel rapor. Yalnizca magaza muduru ve vardiya muduru gorur:
// petty cash durumu, rapor paneli olculeri, ciro hizi ile ay sonu tahmini ve
// urun urun donuk depo yeterliligi.

function fmt(value, type) {
  if (value === null || value === undefined) return '-';
  if (type === 'money') return fmtMoney(value);
  if (type === 'percent') return `${(Number(value) * 100).toFixed(2)}%`;
  if (type === 'int') return Number(value).toLocaleString('tr-TR');
  return Number(value).toFixed(2);
}

const RISK_CLASS = { 0: 'danger', 1: 'danger', 2: 'warning', 3: 'ok' };

export default function ManagerOverview({ overview, fields, windowDays, onWindowChanged }) {
  if (!overview) return null;
  const { petty_cash: pc, revenue: rv, stock } = overview;

  const hasData = rv.days_with_data > 0;
  // Limit asildiginda cubuk tasmasin; renk zaten uyari veriyor.
  const fill = pc.used_pct === null || pc.used_pct === undefined
    ? 0
    : Math.min(1, Math.max(0, Number(pc.used_pct)));
  const barTone = pc.over_limit ? 'danger' : fill >= 0.8 ? 'warning' : 'ok';

  const active = stock.items.filter((i) => i.days_of_cover !== null);
  const idle = stock.items.filter((i) => i.days_of_cover === null);

  return (
    <div className="manager-overview">
      <section className="surface-panel">
        <div className="mo-head">
          <h3><Wallet size={18} /> Petty Cash</h3>
          <span className="muted">
            {pc.limit_set
              ? `Haftalık limit · ${pc.expense_count} masraf kaydı`
              : 'Haftalık limit tanımlanmamış'}
          </span>
        </div>
        <div className="mo-figures">
          <div className="mo-figure">
            <span>Harcanan</span>
            <strong className={pc.over_limit ? 'text-danger' : ''}>{fmtMoney(pc.spent_this_week)}</strong>
          </div>
          <div className="mo-figure">
            <span>Kalan</span>
            <strong className="text-ok">{pc.limit_set ? fmtMoney(pc.remaining) : '-'}</strong>
          </div>
          <div className="mo-figure">
            <span>Limit</span>
            <strong className="muted">{pc.limit_set ? fmtMoney(pc.weekly_limit) : '-'}</strong>
          </div>
        </div>
        {pc.limit_set && (
          <>
            <div className="mo-bar">
              <div className={`mo-bar-fill ${barTone}`} style={{ width: `${fill * 100}%` }} />
            </div>
            <p className={`mo-bar-note ${pc.over_limit ? 'text-danger' : 'muted'}`}>
              {pc.over_limit
                ? `Limit aşıldı: ${fmtMoney(pc.spent_this_week - pc.weekly_limit)} fazla`
                : `${Math.round(fill * 100)}% kullanıldı`}
            </p>
          </>
        )}
      </section>

      <section className="surface-panel">
        <div className="mo-head">
          <h3><TrendingUp size={18} /> Ciro Hızı ve Ay Sonu Tahmini</h3>
          <span className="muted">
            Ay başından bugüne {rv.days_with_data} günün raporu girildi
            {rv.days_missing > 0 ? ` · ${rv.days_missing} gün eksik` : ''}
          </span>
        </div>
        <div className="mo-figures">
          <div className="mo-figure">
            <span>Ay başından bu yana</span>
            <strong>{fmtMoney(rv.mtd_net_sales)}</strong>
          </div>
          <div className="mo-figure">
            <span>Günlük ortalama</span>
            <strong className="text-info">{hasData ? fmtMoney(rv.daily_avg) : '-'}</strong>
          </div>
        </div>
        <div className="mo-forecast">
          <Sparkles size={18} />
          <div>
            <span>Ay sonu tahmini</span>
            <strong>{hasData ? fmtMoney(rv.forecast_month_end) : 'Veri girilmedi'}</strong>
          </div>
          {hasData && <em>{rv.remaining_days} gün kaldı</em>}
        </div>
        {hasData && (
          <p className="muted mo-note">
            Günlük ortalama, rapor girilmiş {rv.days_with_data} güne bölünerek hesaplanır;
            eksik günler sıfır sayılmaz.
          </p>
        )}
        {hasData && fields.derived.length > 0 && (
          <>
            <h4 className="mo-sub">Rapor Paneli — Bu Ay</h4>
            <div className="report-grid">
              {fields.derived.map((f) => (
                <div className="report-cell derived" key={f.key}>
                  <span>{f.label}</span>
                  <strong>{fmt(rv.month_metrics[f.key], f.type)}</strong>
                </div>
              ))}
            </div>
          </>
        )}
      </section>

      <section className="surface-panel">
        <div className="mo-head">
          <h3><Snowflake size={18} /> Donuk Depo Yeterliliği</h3>
          <span className="muted">
            Son {stock.window_days} günün satış hızına göre elimdeki stok kaç gün yeter
          </span>
        </div>
        <div className="chip-row" style={{ marginBottom: 12 }}>
          {[7, 14, 30].map((d) => (
            <button
              key={d}
              type="button"
              className={`chip ${windowDays === d ? 'chip-on' : ''}`}
              onClick={() => onWindowChanged(d)}
            >
              {d} gün
            </button>
          ))}
        </div>
        {stock.items.length === 0 ? (
          <p className="empty">Bu mağazada aktif stok veya satış kaydı yok.</p>
        ) : (
          <>
            <div className="table-wrap">
              <table className="responsive">
                <thead>
                  <tr>
                    <th>Ürün</th><th>Donuk</th><th>Çözülen</th><th>Dolap</th>
                    <th>Satış ({stock.window_days}g)</th><th>Hız/gün</th>
                    <th>Yeterlilik</th><th>Biteceği gün</th>
                  </tr>
                </thead>
                <tbody>
                  {active.map((i) => (
                    <tr key={i.product_type_id}>
                      <td data-label="Ürün">
                        <span className={`mo-dot ${RISK_CLASS[i.risk] || 'ok'}`} />
                        <strong>{i.name}</strong>
                      </td>
                      <td data-label="Donuk">{i.frozen_qty}</td>
                      <td data-label="Çözülen">{i.thawing_qty}</td>
                      <td data-label="Dolap">{i.cabinet_qty}</td>
                      <td data-label="Satış">{i.sold_qty}</td>
                      <td data-label="Hız/gün">{Number(i.daily_velocity).toFixed(2)}</td>
                      <td data-label="Yeterlilik">
                        <strong className={`text-${RISK_CLASS[i.risk] || 'ok'}`}>
                          {i.days_of_cover < 1
                            ? 'bugün biter'
                            : `${Number(i.days_of_cover).toFixed(i.days_of_cover < 10 ? 1 : 0)} gün`}
                        </strong>
                      </td>
                      <td data-label="Biteceği gün">{i.depletion_date ? fmtDate(i.depletion_date) : '-'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {idle.length > 0 && (
              <div className="mo-idle">
                <h4 className="mo-sub">Satış hareketi olmayan {idle.length} çeşit</h4>
                <p className="muted" style={{ fontSize: 12, margin: '0 0 8px' }}>
                  Satış hızı sıfır olduğu için yeterlilik hesaplanamaz.
                </p>
                <div className="chip-row">
                  {idle.map((i) => (
                    <span className="chip" key={i.product_type_id}>
                      {i.name} · {i.frozen_qty} adet
                    </span>
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </section>
    </div>
  );
}
