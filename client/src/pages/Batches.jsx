import { useCallback, useEffect, useMemo, useState } from 'react';
import { Snowflake, Hourglass, Refrigerator, History, PencilLine, Info, PackagePlus, Trash2, Search, Undo2 } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, StatusBadge, Confirm, toast, ActionMenu } from '../components/ui';
import { fmtDateTime, formatHours, errorMessage, toLocalInput, fromLocalInput, addDaysIso, can, STATUS_LABELS } from '../format';

const TABS = [
  { id: 'frozen', label: 'Donuk Depo', ico: Snowflake },
  { id: 'thawing', label: 'Çözünme', ico: Hourglass },
  { id: 'food_cabinet', label: 'Satışa Hazır', ico: Refrigerator },
  { id: 'history', label: 'Geçmiş', ico: History },
];

export default function Batches() {
  const { user } = useAuth();
  const [batches, setBatches] = useState([]);
  const [types, setTypes] = useState([]);
  // Ana sayfadaki ozet kutulari ?tab= ile dogrudan ilgili sekmeyi aciyor.
  const [searchParams] = useSearchParams();
  const requestedTab = searchParams.get('tab');
  const [tab, setTab] = useState(
    () => (['frozen', 'thawing', 'food_cabinet', 'history'].includes(requestedTab) ? requestedTab : 'frozen')
  );
  const [search, setSearch] = useState('');
  const [showAdd, setShowAdd] = useState(false);
  const [showDetail, setShowDetail] = useState(null);
  const [confirmThaw, setConfirmThaw] = useState(null);
  const [confirmComplete, setConfirmComplete] = useState(null);
  const [confirmDiscard, setConfirmDiscard] = useState(null);
  const [earlyRequest, setEarlyRequest] = useState(null);
  const [stockBatch, setStockBatch] = useState(null);
  const [adjustBatch, setAdjustBatch] = useState(null);
  const [correctThaw, setCorrectThaw] = useState(null);
  const [reload, setReload] = useState(0);

  const load = useCallback(() => {
    const status = tab === 'history' ? 'sold,discarded' : tab;
    api.get(`/batches?status=${status}`).then((r) => setBatches(r.data)).catch(() => {});
    api.get('/product-types').then((r) => setTypes(r.data.filter((t) => t.active === 1))).catch(() => {});
  }, [tab]);

  useEffect(() => { load(); }, [load, reload]);

  const shown = useMemo(() => {
    const s = search.trim().toLowerCase();
    if (!s) return batches;
    return batches.filter(
      (b) =>
        (b.product_name || '').toLowerCase().includes(s) ||
        (b.store_name || '').toLowerCase().includes(s)
    );
  }, [batches, search]);

  async function run(action, payload) {
    try {
      await api.post(`/batches/${action.id}/${action.op}`, payload || {}, { successMessage: action.msg });
    } catch {
      // Bildirim API katmaninda gosterilir.
    }
    setReload((n) => n + 1);
  }

  // Silme geri alinamaz: bagli satis ve zayi kayitlari da gider. Onay metni
  // bunu acikca yaziyor ve adet duzeltmesine yonlendiriyor.
  async function removeBatch(b) {
    const ok = window.confirm(
      `${b.product_name} (${STATUS_LABELS[b.status] || b.status}, ${b.remaining} adet kalan) `
      + `kaydı silinecek.\n\nBu partiye ait satış, ikram ve zayi kayıtları da silinir. `
      + `İşlem geri alınamaz.\n\nYalnızca adet yanlışsa silmek yerine `
      + `"Tarih / Adet Düzelt" kullanın.`
    );
    if (!ok) return;
    try {
      await api.delete(`/batches/${b.id}`, { successMessage: 'Kayıt silindi' });
      setReload((n) => n + 1);
    } catch {
      // Bildirim api katmanindan gelir.
    }
  }
  return (
    <div className="page-shell stock-page">
      <div className="page-head">
        <h2>Ürünler</h2>
        <button className="btn btn-primary" onClick={() => setShowAdd(true)}>+ Yeni Ürün</button>
      </div>

      <div className="surface-panel">
        <div className="tabs stock-tabs">
          {TABS.map((t) => (
            <button key={t.id} className={tab === t.id ? 'active' : ''} onClick={() => setTab(t.id)}>
              <t.ico size={17} /> {t.label}
            </button>
          ))}
        </div>

        {/* Öneri Satış Listesi'ndeki arama kutusuyla aynı biçim */}
        <div className="filters" style={{ marginBottom: 0 }}>
          <div className="input-wrap search" style={{ flex: 1 }}>
            <span className="in-ico"><Search size={17} /></span>
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Ürün ara..."
              aria-label="Ürünler arasında ara"
            />
          </div>
          {search.trim() && (
            <button type="button" className="btn btn-sm btn-secondary" onClick={() => setSearch('')}>Temizle</button>
          )}
        </div>
      </div>

      <div className="card table-card">
        <div className="table-wrap">
          <table className="responsive">
            <thead>
              <tr>
                <th>Ürün</th>
                <th>Durum</th>
                <th>Adet</th>
                {user.role === 'super_admin' && <th>Mağaza</th>}
                <th>SKT</th>
                <th style={{ minWidth: 200 }}>İşlemler</th>
              </tr>
            </thead>
            <tbody>
              {shown.length === 0 && (
                <tr><td data-label="" colSpan="7"><p className="empty">Kayıt bulunamadı</p></td></tr>
              )}
              {shown.map((b) => (
                <tr key={b.id}>
                  <td data-label="Ürün"><span><strong>{b.product_name}</strong>{b.notes ? <div className="muted" style={{ fontSize: 12 }}>{b.notes}</div> : null}</span></td>
                  <td data-label="Durum"><StatusBadge status={b.status} urgency={b.urgency} /></td>
                  <td data-label="Adet">{b.remaining}/{b.quantity}</td>
                  {user.role === 'super_admin' && <td data-label="Mağaza">{b.store_name}</td>}
                  <td data-label="SKT" style={{ fontSize: 13 }}>
                    {b.skt_end ? <span>{fmtDateTime(b.skt_end)}<div className="muted" style={{ fontSize: 12 }}>{formatHours(b.remaining_hours)}</div></span> : '-'}
                  </td>
                  <td data-label="İşlemler">
                    <div className="actions stock-actions">
                      {/* Ana islem gorunur kalir, gerisi menuye toplanir: satirlar alcak,
                          tablet ve telefonda tablo cok daha kisa olur. */}
                      {b.status === 'frozen' && (
                        <button className="btn btn-sm btn-primary" onClick={() => setConfirmThaw(b)}>Çözülmeye Al</button>
                      )}
                      {b.status === 'thawing' && b.thaw_ready && (
                        <button className="btn btn-sm btn-success" onClick={() => setConfirmComplete(b)}>Food Dolabına Al</button>
                      )}
                      {b.status === 'thawing' && !b.thaw_ready && b.pending_approval_id && (
                        <span className="badge warning">Onay Bekliyor</span>
                      )}

                      <ActionMenu>
                        <button onClick={() => setShowDetail(b)}><Info size={16} /> Detay</button>
                        {can(user, 'adjust_batches') && (
                          <button onClick={() => setAdjustBatch(b)}><PencilLine size={16} /> Tarih / Adet Düzelt</button>
                        )}
                        {b.status === 'frozen' && (
                          <button onClick={() => setStockBatch(b)}><PackagePlus size={16} /> Stok Ekle</button>
                        )}
                        {b.status === 'thawing' && !b.thaw_ready && !b.pending_approval_id && (
                          <button onClick={() => setEarlyRequest(b)}>
                            <Hourglass size={16} /> Erken Aktarım İste ({formatHours(b.thaw_remaining_hours)})
                          </button>
                        )}
                        {/* Cozulme adedi duzeltmesi yalnizca cozulme surecinde
                            anlamli: food dolabina gecmis urun tekrar dondurulamaz. */}
                        {b.status === 'thawing' && can(user, 'adjust_batches') && (
                          <button onClick={() => setCorrectThaw(b)}>
                            <Undo2 size={16} /> Çözülme Adedini Düzelt
                          </button>
                        )}
                        {['frozen', 'thawing', 'food_cabinet'].includes(b.status) && can(user, 'discard') && (
                          <button className="danger" onClick={() => setConfirmDiscard(b)}><Trash2 size={16} /> Zayi Gir</button>
                        )}
                        {/* Silme geri alinamaz; yalnizca ana yoneticide. */}
                        {user.role === 'super_admin' && (
                          <button className="danger" onClick={() => removeBatch(b)}>
                            <Trash2 size={16} /> Kaydı Sil
                          </button>
                        )}
                      </ActionMenu>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {showAdd && (
        <AddBatchModal types={types} onClose={() => setShowAdd(false)} onDone={() => { setShowAdd(false); setReload((n) => n + 1); }} />
      )}

      {showDetail && <BatchDetail batch={showDetail} onClose={() => setShowDetail(null)} />}

      {confirmThaw && (
        <ThawModal
          batch={confirmThaw}
          onClose={() => setConfirmThaw(null)}
          onDone={() => { setConfirmThaw(null); setReload((n) => n + 1); }}
        />
      )}

      {confirmComplete && (
        <Confirm
          title="Food Dolabına Aktar"
          message={`${confirmComplete.product_name} (${confirmComplete.remaining} adet) çözülme süresi tamamlandığı için food dolabına aktarılacak. SKT süresi bu andan itibaren hesaplanmaya başlayacak.`}
          danger={false}
          confirmLabel="Aktar"
          onCancel={() => setConfirmComplete(null)}
          onConfirm={() => { run({ id: confirmComplete.id, op: 'complete-thaw' }, {}); setConfirmComplete(null); }}
        />
      )}

      {confirmDiscard && (
        <DiscardModal
          batch={confirmDiscard}
          onClose={() => setConfirmDiscard(null)}
          onDone={() => { setConfirmDiscard(null); setReload((n) => n + 1); }}
        />
      )}

      {earlyRequest && (
        <EarlyRequestModal
          batch={earlyRequest}
          onClose={() => setEarlyRequest(null)}
          onDone={() => { setEarlyRequest(null); setReload((n) => n + 1); }}
        />
      )}

      {adjustBatch && (
        <AdjustModal
          batch={adjustBatch}
          onClose={() => setAdjustBatch(null)}
          onDone={() => { setAdjustBatch(null); setReload((n) => n + 1); }}
        />
      )}

      {stockBatch && (
        <StockAddModal
          batch={stockBatch}
          onClose={() => setStockBatch(null)}
          onDone={() => { setStockBatch(null); setReload((n) => n + 1); }}
        />
      )}

      {correctThaw && (
        <CorrectThawModal
          batch={correctThaw}
          onClose={() => setCorrectThaw(null)}
          onDone={() => { setCorrectThaw(null); setReload((n) => n + 1); }}
        />
      )}
    </div>
  );
}

function AddBatchModal({ types, onClose, onDone }) {
  const { user } = useAuth();
  const [product_type_id, setProductType] = useState('');
  const [quantity, setQuantity] = useState(1);
  const [notes, setNotes] = useState('');
  const [store_id, setStoreId] = useState('');
  const [stores, setStores] = useState([]);
  const [err, setErr] = useState('');

  useEffect(() => {
    if (user.role === 'super_admin') api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [user.role]);

  function pickType(id) {
    setProductType(id);
    // mağazaya özel çeşit seçildiyse mağazayı otomatik eşleştir
    const t = types.find((x) => String(x.id) === String(id));
    if (t && t.store_id) setStoreId(String(t.store_id));
  }

  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      const payload = { product_type_id, quantity, notes };
      if (user.role === 'super_admin' && store_id) payload.store_id = Number(store_id);
      await api.post('/batches', payload, { noToast: true });
      toast('Ürün donuk depoya eklendi');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }

  return (
    <Modal title="Yeni Ürün (Donuk Depo)" onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        {user.role === 'super_admin' && (
          <div className="field">
            <label>Mağaza</label>
            <select value={store_id} onChange={(e) => setStoreId(e.target.value)} required>
              <option value="">Seçin...</option>
              {stores.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
        )}
        <div className="field">
          <label>Ürün Çeşidi</label>
          <select value={product_type_id} onChange={(e) => pickType(e.target.value)} required>
            <option value="">Seçin...</option>
            {types.map((t) => (
              <option key={t.id} value={t.id}>{t.name} (SKT {t.skt_days} gün){t.store_id ? '' : ' • Genel'}</option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Adet</label>
          <input type="number" min="1" value={quantity} onChange={(e) => setQuantity(e.target.value)} required />
        </div>
        <div className="field">
          <label>Not (opsiyonel)</label>
          <textarea rows="2" value={notes} onChange={(e) => setNotes(e.target.value)} />
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary">Ekle</button>
        </div>
      </form>
    </Modal>
  );
}

function DiscardModal({ batch, onClose, onDone }) {
  const [reason, setReason] = useState('');
  const [quantity, setQuantity] = useState(batch.remaining);
  const [err, setErr] = useState('');
  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      const r = await api.post(`/batches/${batch.id}/discard`, { reason, quantity }, { noToast: true });
      toast(Number(quantity) >= batch.remaining ? 'Ürünün tamamı zayi verildi' : `${quantity} adet zayi verildi, kalan: ${r.data.remaining}`);
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }
  return (
    <Modal title="Ürüne Zayi Gir" onClose={onClose}>
      <form onSubmit={submit}>
        <p>{batch.product_name} — stokta {batch.remaining} adet var.</p>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Zayi Adedi</label>
          <input type="number" min="1" max={batch.remaining} value={quantity} onChange={(e) => setQuantity(e.target.value)} required />
          <p className="login-hint">Tümüne zayi girmek için {batch.remaining} yaz. Azına girilirse kalan stokta durur.</p>
        </div>
        <div className="field">
          <label>Zayi Sebebi</label>
          <select value={reason} onChange={(e) => setReason(e.target.value)}>
            <option value="">Seçin...</option>
            <option value="SKT süresi doldu">SKT süresi doldu</option>
            <option value="Çözülme süresi aşıldı">Çözülme süresi aşıldı</option>
            <option value="Ürün bozuldu">Ürün bozuldu</option>
            <option value="Diğer">Diğer</option>
          </select>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-danger">Zayi Gir</button>
        </div>
      </form>
    </Modal>
  );
}

function ThawModal({ batch, onClose, onDone }) {
  const [quantity, setQuantity] = useState(batch.remaining);
  const [err, setErr] = useState('');
  const partial = Number(quantity) < batch.remaining;
  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      const r = await api.post(`/batches/${batch.id}/thaw`, { quantity }, { noToast: true });
      toast(partial || r.data.split
        ? `${quantity} adet çözünmeye alındı, kalan ${batch.remaining - Number(quantity)} adet donukta`
        : 'Ürün çözülmeye alındı (+4°C, 8 saat)');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }
  return (
    <Modal title="Çözülmeye Al (+4°C, 8 saat)" onClose={onClose}>
      <form onSubmit={submit}>
        <p><strong>{batch.product_name}</strong> — donuk stok: {batch.remaining} adet.</p>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Çözünmeye Alınacak Adet</label>
          <input type="number" min="1" max={batch.remaining} value={quantity} onChange={(e) => setQuantity(e.target.value)} required autoFocus />
          {partial && (
            <p className="login-hint">{quantity} adet çözünmeye gidecek, {batch.remaining - Number(quantity) || 0} adet donukta kalacak.</p>
          )}
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary">Çözülmeye Al</button>
        </div>
      </form>
    </Modal>
  );
}

function StockAddModal({ batch, onClose, onDone }) {  const [quantity, setQuantity] = useState(1);
  const [err, setErr] = useState('');
  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      await api.post(`/batches/${batch.id}/add-stock`, { quantity }, { noToast: true });
      toast(`${quantity} adet donuk stoka eklendi`);
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }
  return (
    <Modal title="Donuk Stok Ekle" onClose={onClose}>
      <form onSubmit={submit}>
        <p><strong>{batch.product_name}</strong> — mevcut stok: {batch.remaining} adet.</p>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Eklenecek Adet</label>
          <input type="number" min="1" value={quantity} onChange={(e) => setQuantity(e.target.value)} required autoFocus />
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary">Stoka Ekle</button>
        </div>
      </form>
    </Modal>
  );
}


function EarlyRequestModal({ batch, onClose, onDone }) {
  const [reason, setReason] = useState('');
  const [err, setErr] = useState('');
  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      await api.post(`/batches/${batch.id}/request-early-transfer`, { reason }, { noToast: true });
      toast('Erken aktarım isteği yönetici onayına gönderildi');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }
  return (
    <Modal title="Erken Aktarım İsteği" onClose={onClose}>
      <form onSubmit={submit}>
        <p>
          <strong>{batch.product_name}</strong> ({batch.remaining} adet) çözünme süresi dolmadan
          food dolabına alınmak isteniyor. Çözülmeye kalan süre: <strong>{formatHours(batch.thaw_remaining_hours)}</strong>.
          Mağaza yöneticisi onaylarsa aktarım gerçekleşir.
        </p>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Erken Aktarım Nedeni</label>
          <textarea rows="3" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="örn: Müşteri siparişi için acil ihtiyaç var" required />
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary">Onaya Gönder</button>
        </div>
      </form>
    </Modal>
  );
}

function BatchDetail({ batch, onClose }) {  const [sales, setSales] = useState([]);
  useEffect(() => {
    api.get(`/batches/${batch.id}`).then((r) => setSales(r.data.sales || [])).catch(() => {});
  }, [batch.id]);
  return (
    <Modal title={`Ürün Detayı — ${batch.product_name}`} onClose={onClose}>
      <div className="field"><label>Durum</label><StatusBadge status={batch.status} urgency={batch.urgency} /></div>
      <div className="field"><label>Miktar</label><div>{batch.remaining} / {batch.quantity} adet</div></div>
      <div className="field"><label>Donuk Depoya Giriş</label><div>{fmtDateTime(batch.entered_frozen_at)}</div></div>
      {batch.thawing_started_at && <div className="field"><label>Çözülme Başlangıcı</label><div>{fmtDateTime(batch.thawing_started_at)}</div></div>}
      {batch.thawing_finish_at && <div className="field"><label>Çözülme Bitişi</label><div>{fmtDateTime(batch.thawing_finish_at)}</div></div>}
      {batch.food_cabinet_entered_at && <div className="field"><label>Food Dolabına Giriş</label><div>{fmtDateTime(batch.food_cabinet_entered_at)}</div></div>}
      {batch.skt_end && <div className="field"><label>SKT Bitiş</label><div>{fmtDateTime(batch.skt_end)}</div></div>}
      {batch.notes && <div className="field"><label>Not</label><div>{batch.notes}</div></div>}

      <h4 style={{ marginBottom: 8 }}>Satış Geçmişi</h4>
      {sales.length === 0 ? (
        <p className="empty">Henüz satış yok</p>
      ) : (
        <table>
          <thead><tr><th>Tarih</th><th>Adet</th><th>Birim</th><th>Satış Yapan</th></tr></thead>
          <tbody>
            {sales.map((s) => (
              <tr key={s.id}>
                <td>{fmtDateTime(s.sold_at)}</td>
                <td>{s.quantity}</td>
                <td>{s.unit_price ? `${s.unit_price.toLocaleString('tr-TR')} TL` : '-'}</td>
                <td>{s.sold_by_name || '-'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <div className="form-actions"><button className="btn btn-secondary" onClick={onClose}>Kapat</button></div>
    </Modal>
  );
}

// Ana Yonetici duzeltmesi: yanlis girilen tarih/saat ve adetleri duzeltir.
function AdjustModal({ batch, onClose, onDone }) {
  const [quantity, setQuantity] = useState(batch.quantity);
  const [remaining, setRemaining] = useState(batch.remaining);
  const [stamps, setStamps] = useState({
    entered_frozen_at: toLocalInput(batch.entered_frozen_at),
    thawing_started_at: toLocalInput(batch.thawing_started_at),
    thawing_finish_at: toLocalInput(batch.thawing_finish_at),
    food_cabinet_entered_at: toLocalInput(batch.food_cabinet_entered_at),
    skt_end: toLocalInput(batch.skt_end),
  });
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  // Kaydin gectigi asamalara ait alanlar gosterilir; donuk depo girisi her zaman var.
  const fields = [
    { key: 'entered_frozen_at', label: 'Donuk Depoya Giriş', always: true },
    { key: 'thawing_started_at', label: 'Çözülme Başlangıcı' },
    { key: 'thawing_finish_at', label: 'Çözülme Bitişi' },
    { key: 'food_cabinet_entered_at', label: 'Food Dolabına Giriş' },
    { key: 'skt_end', label: 'SKT Bitiş' },
  ].filter((f) => f.always || batch[f.key]);

  function setStamp(key, value) {
    setStamps((prev) => {
      const next = { ...prev, [key]: value };
      // Food dolabina giris degisince SKT bitisi cesidin SKT gunune gore yeniden
      // hesaplanir; yonetici isterse asagidaki alandan yine elle degistirebilir.
      if (key === 'food_cabinet_entered_at' && prev.skt_end && batch.skt_days) {
        const recomputed = addDaysIso(fromLocalInput(value), Number(batch.skt_days));
        if (recomputed) next.skt_end = toLocalInput(recomputed);
      }
      return next;
    });
  }

  async function submit(e) {
    e.preventDefault();
    setErr('');
    setBusy(true);
    const payload = { quantity: Number(quantity), remaining: Number(remaining) };
    for (const f of fields) payload[f.key] = fromLocalInput(stamps[f.key]);
    try {
      const r = await api.put(`/batches/${batch.id}/adjust`, payload, { noToast: true });
      toast(r.data.changes && r.data.changes.length ? 'Kayıt düzeltildi' : 'Değişiklik yapılmadı');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title={`Kaydı Düzelt — ${batch.product_name}`} onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <p className="muted" style={{ fontSize: 13, marginTop: 0 }}>
          Yanlış girilen tarih/saat ve adetleri düzeltir. Ürünün durumu değişmez ve
          yapılan düzeltme hareket kayıtlarına yazılır.
        </p>

        <div className="field">
          <label>Toplam Adet</label>
          <input type="number" min="1" value={quantity} onChange={(e) => setQuantity(e.target.value)} required />
        </div>
        <div className="field">
          <label>Kalan Adet</label>
          <input type="number" min="0" value={remaining} onChange={(e) => setRemaining(e.target.value)} required />
          <small className="muted">Kalan adet toplam adetten büyük olamaz.</small>
        </div>

        {fields.map((f) => (
          <div className="field" key={f.key}>
            <label>{f.label}</label>
            <input
              type="datetime-local"
              value={stamps[f.key]}
              onChange={(e) => setStamp(f.key, e.target.value)}
              required={f.key === 'entered_frozen_at'}
            />
            {f.key === 'food_cabinet_entered_at' && batch.skt_days ? (
              <small className="muted">Bu tarih değişince SKT bitişi {batch.skt_days} güne göre yeniden hesaplanır.</small>
            ) : null}
          </div>
        ))}

        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? 'Kaydediliyor...' : 'Düzeltmeyi Kaydet'}
          </button>
        </div>
      </form>
    </Modal>
  );
}

/// Cozulmeye alinan adedi duzeltir; fark donuk depoya geri doner.
///
/// 0 girilirse parti cozulmeden tamamen cikar. Fark once ayni partiden
/// bolunmus donuk kardese eklenir, yoksa donma tarihi korunarak yeni donuk
/// parti acilir.
function CorrectThawModal({ batch, onClose, onDone }) {
  const [quantity, setQuantity] = useState(String(batch.remaining));
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  const entered = Number.parseInt(quantity, 10);
  const back = Number.isInteger(entered) && entered >= 0 && entered <= batch.remaining
    ? batch.remaining - entered
    : null;

  async function submit(e) {
    e.preventDefault();
    setErr('');
    if (!Number.isInteger(entered) || entered < 0) {
      setErr('Doğru adet 0 veya daha büyük bir tam sayı olmalıdır'); return;
    }
    if (entered > batch.remaining) {
      setErr(`Doğru adet mevcut adetten (${batch.remaining}) büyük olamaz`); return;
    }
    if (entered === batch.remaining) { setErr('Adet değişmedi'); return; }
    setBusy(true);
    try {
      await api.post(`/batches/${batch.id}/correct-thaw-quantity`, { quantity: entered },
        { noToast: true, busyMessage: 'Adet düzeltiliyor...' });
      toast('Adet düzeltildi');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="Çözülme Adedini Düzelt" onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <p className="muted" style={{ fontSize: 13, margin: '0 0 12px' }}>
          {batch.product_name} — şu anda {batch.remaining} adet çözülmede.
        </p>
        <div className="field">
          <label>Doğru Adet</label>
          <input value={quantity} onChange={(e) => setQuantity(e.target.value)}
            inputMode="numeric" required />
          <p className="muted" style={{ fontSize: 12, margin: '4px 0 0' }}>
            0 yazarsanız ürün tamamen donuk depoya döner.
          </p>
        </div>
        {back !== null && back > 0 && (
          <div className="system-box">
            <p className="system-box-title">
              {back} adet donuk depoya geri dönecek. Dondurucuya giriş tarihi korunur.
            </p>
          </div>
        )}
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
