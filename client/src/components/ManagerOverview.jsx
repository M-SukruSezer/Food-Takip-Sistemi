import { Link } from 'react-router-dom';
import { Sparkles, TrendingUp, Wallet, ChevronRight } from 'lucide-react';
import { fmtMoney } from '../format';

// Ana sayfadaki genel rapor. Yalnizca magaza muduru ve vardiya muduru gorur.
//
// Sira istenen gibi: 1) Ciro Forecast, 2) Petty Cash. Ikisi de tiklanabilir ve
// ilgili modulu acar. Stok yeterliligi ana sayfada cok yer kapladigi icin
// kendi moduluna tasindi (/stock-coverage).

function fmt(value, type) {
  if (value === null || value === undefined) return '-';
  if (type === 'money') return fmtMoney(value);
  if (type === 'percent') return `${(Number(value) * 100).toFixed(2)}%`;
  if (type === 'int') return Number(value).toLocaleString('tr-TR');
  return Number(value).toFixed(2);
}

export default function ManagerOverview({ overview, fields }) {
  if (!overview) return null;
  const { petty_cash: pc, revenue: rv } = overview;

  const hasData = rv.days_with_data > 0;
  // Limit asildiginda cubuk tasmasin; renk zaten uyari veriyor.
  const fill = pc.used_pct === null || pc.used_pct === undefined
    ? 0
    : Math.min(1, Math.max(0, Number(pc.used_pct)));
  const barTone = pc.over_limit ? 'danger' : fill >= 0.8 ? 'warning' : 'ok';

  return (
    <div className="manager-overview">
      <Link to="/daily-report" className="surface-panel mo-link">
        <div className="mo-head">
          <h3><TrendingUp size={18} /> Ciro Forecast <ChevronRight size={18} className="mo-go" /></h3>
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
      </Link>
      <Link to="/petty-cash" className="surface-panel mo-link">
        <div className="mo-head">
          <h3><Wallet size={18} /> Petty Cash <ChevronRight size={18} className="mo-go" /></h3>
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
      </Link>
    </div>
  );
}
