import { useCallback, useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Banknote, Pencil, Trash2 } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, toast } from '../components/ui';
import { fmtDateTime, fmtMoney, errorMessage, can } from '../format';

// Sunucudaki allowedKinds ile ayni.
const KINDS = [
  { key: 'sale', label: 'Satış', badge: 'sold' },
  { key: 'ikram', label: 'İkram', badge: 'warning' },
  { key: 'discard', label: 'Zayi', badge: 'discarded' },
];

// Hazir tarih araliklari. "all" filtre gondermez; sunucu son 1000 hareketi doner.
const RANGES = [
  { key: 'today', label: 'Bugün', days: 0 },
  { key: 'week', label: 'Son 7 gün', days: 6 },
  { key: 'month', label: 'Son 30 gün', days: 29 },
  { key: 'all', label: 'Tümü', days: null },
];

function dayString(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

const EMPTY_TOTALS = {
  sale_qty: 0, revenue: 0, ikram_qty: 0, ikram_value: 0,
  discard_qty: 0, discard_value: 0, count: 0,
};

export default function Sales() {
  const [correcting, setCorrecting] = useState(null);
  // Duzeltme/silme sonrasi listeyi yeniler.
  const [reload, setReload] = useState(0);
  const { user } = useAuth();
  const [items, setItems] = useState([]);
  const [totals, setTotals] = useState(EMPTY_TOTALS);
  const [stores, setStores] = useState([]);
  const [types, setTypes] = useState([]);

  // Ana sayfadaki ozet kutulari ?range= ve ?kind= ile filtreli aciyor.
  const [searchParams] = useSearchParams();
  const [range, setRange] = useState(() => {
    const requested = searchParams.get('range');
    return RANGES.some((r) => r.key === requested) ? requested : 'month';
  });
  const [customFrom, setCustomFrom] = useState('');
  const [customTo, setCustomTo] = useState('');
  const [productTypeId, setProductTypeId] = useState('');
  const [kinds, setKinds] = useState(() => {
    const requested = searchParams.get('kind');
    return KINDS.some((k) => k.key === requested) ? [requested] : KINDS.map((k) => k.key);
  });
  const [storeId, setStoreId] = useState('');

  // Ozel aralik secilince hazir araliklar birakilir.
  const bounds = useMemo(() => {
    if (range === 'custom') return { from: customFrom || null, to: customTo || null };
    const preset = RANGES.find((r) => r.key === range);
    if (!preset || preset.days === null) return { from: null, to: null };
    const today = new Date();
    const start = new Date(today.getTime() - preset.days * 86400000);
    return { from: dayString(start), to: dayString(today) };
  }, [range, customFrom, customTo]);

  const load = useCallback(() => {
    const params = new URLSearchParams();
    if (bounds.from) params.set('from', bounds.from);
    if (bounds.to) params.set('to', bounds.to);
    if (productTypeId) params.set('productTypeId', productTypeId);
    // Hepsi seciliyse parametre gonderilmez.
    if (kinds.length > 0 && kinds.length < KINDS.length) params.set('kind', kinds.join(','));
    if (storeId) params.set('storeId', storeId);
    const q = params.toString();
    api.get('/reports/movements' + (q ? `?${q}` : ''))
      .then((r) => {
        setItems(r.data.items || []);
        setTotals(r.data.totals || EMPTY_TOTALS);
      })
      .catch(() => {});
  }, [bounds, productTypeId, kinds, storeId]);

  useEffect(() => { load(); }, [load, reload]);

  useEffect(() => {
    api.get('/product-types', { silent: true }).then((r) => setTypes(r.data)).catch(() => {});
    if (user.role === 'super_admin') {
      api.get('/stores', { silent: true }).then((r) => setStores(r.data)).catch(() => {});
    }
  }, [user.role]);

  function toggleKind(key) {
    setKinds((list) => {
      if (!list.includes(key)) return [...list, key];
      // En az bir tur secili kalmali; hepsi kapaliyken liste anlamsiz olur.
      return list.length > 1 ? list.filter((k) => k !== key) : list;
    });
  }

  const canAdjust = can(user, 'adjust_batches');

  // Kayit silinince adedin tamami stoga doner; onay metni bunu yaziyor.
  async function removeMovement(m) {
    const ok = window.confirm(
      `${m.product_name} — ${m.quantity} adet\n\n`
      + `Kayıt silinecek ve ${m.quantity} adet stoka geri dönecek.`
    );
    if (!ok) return;
    try {
      const path = m.kind === 'discard' ? `/discards/${m.id}` : `/sales/${m.id}`;
      await api.delete(path, { successMessage: 'Kayıt silindi, adet stoka döndü' });
      setReload((n) => n + 1);
    } catch {
      // Bildirim api katmanindan gelir.
    }
  }

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Banknote size={20} /> Hareket Raporu</h2>
        <span className="muted">Satış, ikram ve zayi kayıtları</span>
      </div>

      <div className="surface-panel">
        <div className="report-filter">
          <div className="report-filter-group">
            <span className="report-filter-label">Tarih</span>
            <div className="chip-row">
              {RANGES.map((r) => (
                <button
                  key={r.key}
                  type="button"
                  className={`chip ${range === r.key ? 'chip-on' : ''}`}
                  aria-pressed={range === r.key}
                  onClick={() => setRange(r.key)}
                >
                  {r.label}
                </button>
              ))}
              <button
                type="button"
                className={`chip ${range === 'custom' ? 'chip-on' : ''}`}
                aria-pressed={range === 'custom'}
                onClick={() => setRange('custom')}
              >
                Özel aralık
              </button>
            </div>
          </div>

          {range === 'custom' && (
            <div className="report-filter-group">
              <span className="report-filter-label">Başlangıç / Bitiş</span>
              <div className="chip-row">
                <input type="date" value={customFrom} onChange={(e) => setCustomFrom(e.target.value)} />
                <input type="date" value={customTo} onChange={(e) => setCustomTo(e.target.value)} />
              </div>
            </div>
          )}

          <div className="report-filter-group">
            <span className="report-filter-label">Hareket Türü</span>
            <div className="chip-row">
              {KINDS.map((k) => (
                <button
                  key={k.key}
                  type="button"
                  className={`chip ${kinds.includes(k.key) ? 'chip-on' : ''}`}
                  aria-pressed={kinds.includes(k.key)}
                  onClick={() => toggleKind(k.key)}
                >
                  {k.label}
                </button>
              ))}
            </div>
          </div>

          <div className="report-filter-group">
            <span className="report-filter-label">Ürün</span>
            <select value={productTypeId} onChange={(e) => setProductTypeId(e.target.value)}>
              <option value="">Tüm ürünler</option>
              {types.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
          </div>

          {user.role === 'super_admin' && (
            <div className="report-filter-group">
              <span className="report-filter-label">Mağaza</span>
              <select value={storeId} onChange={(e) => setStoreId(e.target.value)}>
                <option value="">Tüm Mağazalar</option>
                {stores.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </div>
          )}
        </div>

        <div className="grid stats">
          <div className="stat stat-card">
            <div className="label"><span>Satış Adedi</span></div>
            <div className="value">{totals.sale_qty}</div>
            <div className="sub">{totals.count} hareket</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span>Ciro</span></div>
            <div className="value">{fmtMoney(totals.revenue)}</div>
            <div className="sub">yalnızca satışlar</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span>İkram Edilen</span></div>
            <div className="value">{totals.ikram_qty}</div>
            <div className="sub">değeri {fmtMoney(totals.ikram_value)}</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span>Zayi Verilen</span></div>
            <div className="value">{totals.discard_qty}</div>
            <div className="sub">değeri {fmtMoney(totals.discard_value)}</div>
          </div>
        </div>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr>
                <th>Ürün</th><th>Tür</th><th>Adet</th><th>Birim</th><th>Tutar</th>
                <th>Kullanıcı</th><th>Tarih</th><th>İşlem</th>
              </tr>
            </thead>
            <tbody>
              {items.length === 0 && (
                <tr><td data-label="" colSpan="8"><p className="empty">Seçtiğiniz filtrelerde hareket bulunamadı.</p></td></tr>
              )}
              {items.map((m) => {
                const kind = KINDS.find((k) => k.key === m.kind) || KINDS[0];
                return (
                  <tr key={`${m.kind}-${m.id}`}>
                    <td data-label="Ürün">
                      <strong>{m.product_name}</strong>
                      {m.reason && <div className="muted" style={{ fontSize: 12 }}>{m.reason}</div>}
                    </td>
                    <td data-label="Tür"><span className={`badge ${kind.badge}`}>{kind.label}</span></td>
                    <td data-label="Adet">{m.quantity}</td>
                    <td data-label="Birim">
                      {m.unit_price === null || m.unit_price === undefined ? '-' : fmtMoney(m.unit_price)}
                      {/* Zayide tutar anlik goruntu degil, cesidin guncel fiyati. */}
                      {m.price_is_current && m.unit_price !== null && (
                        <div className="muted" style={{ fontSize: 11 }}>güncel fiyat</div>
                      )}
                    </td>
                    <td data-label="Tutar">{m.total === null || m.total === undefined ? '-' : fmtMoney(m.total)}</td>
                    <td data-label="Kullanıcı">{m.user_name || '-'}</td>
                    <td data-label="Tarih" className="muted" style={{ fontSize: 13 }}>{fmtDateTime(m.at)}</td>
                    <td data-label="İşlem">
                      {/* Geriye donuk adet duzeltmesi; sunucu ayni yetkiyi ariyor. */}
                      {canAdjust && (
                        <div className="row-actions">
                          <button className="btn btn-sm btn-secondary" title="Adedi düzelt"
                            onClick={() => setCorrecting(m)}>
                            <Pencil size={14} />
                          </button>
                          <button className="btn btn-sm btn-danger" title="Kaydı sil"
                            onClick={() => removeMovement(m)}>
                            <Trash2 size={14} />
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {correcting && (
        <CorrectModal
          movement={correcting}
          onClose={() => setCorrecting(null)}
          onDone={() => { setCorrecting(null); setReload((n) => n + 1); }}
        />
      )}
    </div>
  );
}

/// Satis, ikram veya zayi kaydinin adedini geriye donuk duzeltir.
///
/// Adet azaltilirsa fark stoga geri doner, artirilirsa stoktan duser. Rapor
/// paneli food rakamlarini bu kayitlardan canli hesapladigi icin duzeltme
/// gecmis gunlerin raporuna da yansir.
function CorrectModal({ movement: m, onClose, onDone }) {
  const isDiscard = m.kind === 'discard';
  const [quantity, setQuantity] = useState(String(m.quantity));
  const [reason, setReason] = useState(m.reason || '');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  const entered = Number.parseInt(quantity, 10);
  const delta = Number.isInteger(entered) && entered >= 1 ? m.quantity - entered : null;

  async function submit(e) {
    e.preventDefault();
    setErr('');
    if (!Number.isInteger(entered) || entered < 1) { setErr('Adet en az 1 olmalıdır'); return; }
    if (entered === m.quantity && (!isDiscard || reason.trim() === (m.reason || ''))) {
      setErr('Değişiklik yapılmadı'); return;
    }
    setBusy(true);
    try {
      const path = isDiscard ? `/discards/${m.id}` : `/sales/${m.id}`;
      const body = isDiscard
        ? { quantity: entered, reason: reason.trim() }
        : { quantity: entered };
      await api.put(path, body, { noToast: true, busyMessage: 'Adet düzeltiliyor...' });
      toast('Adet düzeltildi');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }

  const label = (KINDS.find((k) => k.key === m.kind) || KINDS[0]).label;

  return (
    <Modal title={`${label} Adedini Düzelt`} onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <p className="muted" style={{ fontSize: 13, margin: '0 0 12px' }}>
          {m.product_name} — {fmtDateTime(m.at)}<br />
          Kayıtlı adet: {m.quantity}
        </p>
        <div className="field">
          <label>Doğru Adet</label>
          <input value={quantity} onChange={(e) => setQuantity(e.target.value)}
            inputMode="numeric" required />
        </div>
        {isDiscard && (
          <div className="field">
            <label>Zayi Sebebi</label>
            <input value={reason} onChange={(e) => setReason(e.target.value)} />
          </div>
        )}
        {delta !== null && delta !== 0 && (
          <div className="system-box">
            <p className="system-box-title">
              {delta > 0
                ? `${delta} adet stoka geri dönecek.`
                : `${-delta} adet stoktan düşecek. Yeterli stok yoksa işlem reddedilir.`}
            </p>
          </div>
        )}
        <p className="muted" style={{ fontSize: 12 }}>
          Rapor panelindeki FOOD rakamları bu kayıtlardan hesaplandığı için düzeltme
          o günün raporuna da yansır.
        </p>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Düzeltiliyor...' : 'Düzelt'}
          </button>
        </div>
      </form>
    </Modal>
  );
}
