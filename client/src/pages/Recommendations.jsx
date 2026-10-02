import { useCallback, useEffect, useMemo, useState } from 'react';
import { Flame, Search, TriangleAlert, Clock3, CheckCircle2 } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { SellConfirmModal } from '../components/ui';
import { DiscardModal } from './Batches';
import { fmtDateTime, normalizeSearch, can } from '../format';

export default function Recommendations() {
  const { user } = useAuth();
  const [items, setItems] = useState([]);
  const [reload, setReload] = useState(0);
  const [sellBatch, setSellBatch] = useState(null);
  const [ikramBatch, setIkramBatch] = useState(null);
  const [confirmDiscard, setConfirmDiscard] = useState(null);
  const [search, setSearch] = useState('');

  const load = useCallback(() => {
    api.get('/recommendations').then((r) => setItems(r.data)).catch(() => {});
  }, []);

  useEffect(() => { load(); }, [load, reload]);

  const shown = useMemo(() => {
    const q = normalizeSearch(search.trim());
    if (!q) return items;
    return items.filter(
      (i) => normalizeSearch(i.product_name).includes(q) || normalizeSearch(i.store_name).includes(q)
    );
  }, [items, search]);

  const grouped = useMemo(() => {
    const critical = shown.filter((i) => i.urgency === 'critical' || i.urgency === 'expired');
    const warning = shown.filter((i) => i.urgency === 'warning');
    const normal = shown.filter((i) => i.urgency === 'normal');
    return { critical, warning, normal };
  }, [shown]);

  // SKT uyarisi guvenlik sinyali: aramaya bakmaksizin tum dolabi kapsar.
  const expired = items.filter((i) => i.urgency === 'expired');
  const filtering = search.trim().length > 0;
  const sum = (list) => list.reduce((s, i) => s + i.remaining, 0);

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Flame size={20} /> Öneri Satış Listesi</h2>
        <span className="muted">Food dolabındaki tüm ürünler, SKT'si en yakın olan en üstte</span>
      </div>

      {expired.length > 0 && (
        <div className="urgent-banner">
          <span className="icon-chip"><TriangleAlert size={20} /></span>
          <span className="urgent-copy">
            <span className="urgent-kicker">Acil Operasyonel Aksiyon</span>
            <p className="urgent-title">{sum(expired)} adet ürünün SKT'si doldu!</p>
            <p className="urgent-sub">Lütfen zayi girin veya satışı durdurun.</p>
          </span>
        </div>
      )}

      <div className="surface-panel tier-summary">
        <div className="grid stats">
          <div className="stat stat-card">
            <span className="icon-chip danger"><TriangleAlert size={16} /></span>
            <div className="label"><span>Son Gün</span></div>
            <div className="value" style={{ color: 'var(--danger)' }}>{sum(grouped.critical)}</div>
            <div className="sub">{grouped.critical.length} kayıt öncelikli</div>
          </div>
          <div className="stat stat-card">
            <span className="icon-chip warning"><Clock3 size={16} /></span>
            <div className="label"><span>2 Gün</span></div>
            <div className="value" style={{ color: 'var(--warning)' }}>{sum(grouped.warning)}</div>
            <div className="sub">{grouped.warning.length} kayıt</div>
          </div>
          <div className="stat stat-card">
            <span className="icon-chip success"><CheckCircle2 size={16} /></span>
            <div className="label"><span>3 Gün</span></div>
            <div className="value" style={{ color: 'var(--success)' }}>{sum(grouped.normal)}</div>
            <div className="sub">{grouped.normal.length} kayıt</div>
          </div>
        </div>

        <div className="filters" style={{ marginBottom: 0 }}>
          <div className="input-wrap search" style={{ flex: 1 }}>
            <span className="in-ico"><Search size={17} /></span>
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Ürün ara..."
              aria-label="Öneri listesinde ürün ara"
            />
          </div>
          {filtering && (
            <button type="button" className="btn btn-sm btn-secondary" onClick={() => setSearch('')}>Temizle</button>
          )}
        </div>
        {filtering && (
          <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '8px 0 0' }}>
            Arama etkin: {items.length} üründen {shown.length} tanesi gösteriliyor. Kademe sayıları da bu sonuca göre.
          </p>
        )}
      </div>

      {items.length === 0 ? (
        <div className="card"><p className="empty">Food dolabında satışa hazır ürün bulunmuyor.</p></div>
      ) : shown.length === 0 ? (
        <div className="card"><p className="empty">"{search}" ile eşleşen ürün bulunamadı.</p></div>
      ) : (
        <div className="recommendation-list">
          {shown.map((b) => (
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
                  <>
                    <button className="btn btn-sm btn-success" onClick={() => setSellBatch(b)}>Satış</button>
                    {/* Yetkisi olmayan kullanicida dugme hic cizilmez; sunucu da reddeder. */}
                    {can(user, 'ikram') && (
                      <button className="btn btn-sm btn-secondary" onClick={() => setIkramBatch(b)}>İkram</button>
                    )}
                  </>
                )}
                {can(user, 'discard') && (
                  <button className="btn btn-sm btn-outline-danger" onClick={() => setConfirmDiscard(b)}>Zayi</button>
                )}
              </div>
            </article>
          ))}
        </div>
      )}

      <p className="muted" style={{ fontSize: 'var(--fs-body)' }}>
        Liste anlıktır: satış veya ikram işaretlendiğinde stok azalır, tükenen ürünler listeden
        otomatik düşer. İkram ciroya eklenmez, ayrı raporlanır.
      </p>

      {sellBatch && (
        <SellConfirmModal
          batch={sellBatch}
          kind="sale"
          onCancel={() => setSellBatch(null)}
          onConfirm={async () => {
            try {
              await api.post(`/batches/${sellBatch.id}/sell`, { quantity: 1 }, {
                successMessage: `${sellBatch.product_name} — 1 adet satıldı`,
              });
            } catch {
              // Bildirim API katmaninda gosterilir.
            }
            setSellBatch(null);
            setReload((n) => n + 1);
          }}
        />
      )}

      {ikramBatch && (
        <SellConfirmModal
          batch={ikramBatch}
          kind="ikram"
          onCancel={() => setIkramBatch(null)}
          onConfirm={async () => {
            try {
              await api.post(`/batches/${ikramBatch.id}/sell`, { quantity: 1, kind: 'ikram' }, {
                successMessage: `${ikramBatch.product_name} — 1 adet ikram edildi`,
              });
            } catch {
              // Bildirim API katmaninda gosterilir.
            }
            setIkramBatch(null);
            setReload((n) => n + 1);
          }}
        />
      )}

      {confirmDiscard && (
        <DiscardModal
          batch={confirmDiscard}
          fixedQuantity={1}
          onClose={() => setConfirmDiscard(null)}
          onDone={() => { setConfirmDiscard(null); setReload((n) => n + 1); }}
        />
      )}
    </div>
  );
}
