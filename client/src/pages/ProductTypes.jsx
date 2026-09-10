import { useCallback, useEffect, useState } from 'react';
import { Cake } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, Confirm, toast } from '../components/ui';
import { errorMessage } from '../format';

export default function ProductTypes() {
  const { user } = useAuth();
  const [types, setTypes] = useState([]);
  const [stores, setStores] = useState([]);
  const [reload, setReload] = useState(0);
  const [showAdd, setShowAdd] = useState(false);
  const [edit, setEdit] = useState(null);
  const [del, setDel] = useState(null);
  const canManage = user.role === 'super_admin';

  const load = useCallback(() => {
    api.get('/product-types').then((r) => setTypes(r.data)).catch(() => {});
    if (user.role === 'super_admin') api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [user.role]);

  useEffect(() => { load(); }, [load, reload]);

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Cake size={20} /> Pasta Çeşitleri ve SKT Süreleri</h2>
        {canManage && <button className="btn btn-primary" onClick={() => setShowAdd(true)}>+ Yeni Çeşit</button>}
      </div>
      {!canManage && (
        <div className="surface-panel">
          <p className="muted" style={{ fontSize: 13, margin: 0 }}>
            Pasta çeşitleri ve SKT süreleri Ana Yönetici tarafından tanımlanır. Ürün eklerken bu listeden seçim yapabilirsin.
          </p>
        </div>
      )}

      <div className="grid products">
        {types.map((t) => (
          <div className="card" key={t.id} style={{ marginBottom: 0, display: 'flex', flexDirection: 'column', gap: 8 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div>
                <strong style={{ fontSize: 16 }}>{t.name}</strong>
                {!t.active && <span className="pill r" style={{ marginLeft: 6 }}>pasif</span>}
                <div className="muted" style={{ fontSize: 13 }}>{t.description || 'Açıklama yok'}</div>
              </div>
            </div>
            <div>
              <span className={`pill ${t.skt_days === 3 ? 'o' : 'g'}`}>SKT: {t.skt_days} gün</span>
              {!t.store_id
                ? <span className="pill g">Genel</span>
                : (user.role === 'super_admin' && <span className="pill g">{t.store_name}</span>)}
            </div>
            {canManage && (
              <div className="actions" style={{ marginTop: 'auto' }}>
                <button className="btn btn-sm btn-secondary" onClick={() => setEdit(t)}>Düzenle</button>
                <button className="btn btn-sm btn-outline-danger" onClick={() => setDel(t)}>Sil</button>
              </div>
            )}
          </div>
        ))}
      </div>

      {types.length === 0 && <div className="card"><p className="empty">Henüz ürün çeşidi eklenmemiş.</p></div>}

      {showAdd && (
        <TypeModal
          stores={stores}
          defaultStore={user.store_id}
          onClose={() => setShowAdd(false)}
          onDone={() => { setShowAdd(false); setReload((n) => n + 1); }}
        />
      )}
      {edit && (
        <TypeModal
          type={edit}
          stores={stores}
          onClose={() => setEdit(null)}
          onDone={() => { setEdit(null); setReload((n) => n + 1); }}
        />
      )}
      {del && (
        <Confirm
          title="Çeşidi Sil"
          message={`${del.name} çeşidi silinecek. Bu çeşide ait ürün kaydı varsa silinemez, pasife alınabilir.`}
          confirmLabel="Sil"
          onCancel={() => setDel(null)}
          onConfirm={async () => {
            try {
              await api.delete(`/product-types/${del.id}`);
              toast('Çeşit silindi');
            } catch (e) {
              toast(errorMessage(e));
            }
            setDel(null);
            setReload((n) => n + 1);
          }}
        />
      )}
    </div>
  );
}

function TypeModal({ type, stores, defaultStore, onClose, onDone }) {
  const { user } = useAuth();
  const [name, setName] = useState(type?.name || '');
  const [skt_days, setSkt] = useState(type?.skt_days || 3);
  const [description, setDesc] = useState(type?.description || '');
  const [active, setActive] = useState(type ? type.active === 1 : true);
  const [store_id, setStoreId] = useState(type?.store_id || defaultStore || '');
  const [err, setErr] = useState('');

  async function submit(e) {
    e.preventDefault();
    setErr('');
    const payload = { name, skt_days: Number(skt_days), description, active };
    if (user.role === 'super_admin') payload.store_id = store_id === '' ? null : Number(store_id);
    try {
      if (type) {
        await api.put(`/product-types/${type.id}`, payload);
        toast('Çeşit güncellendi');
      } else {
        await api.post('/product-types', payload);
        toast('Çeşit eklendi');
      }
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }

  return (
    <Modal title={type ? 'Çeşidi Düzenle' : 'Yeni Pasta Çeşidi'} onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Ürün Adı</label>
          <input value={name} onChange={(e) => setName(e.target.value)} required />
        </div>
        <div className="field">
          <label>SKT Süresi (gün)</label>
          <div style={{ display: 'flex', gap: 8 }}>
            {[3, 4].map((d) => (
              <button
                type="button"
                key={d}
                className={`btn ${Number(skt_days) === d ? 'btn-primary' : 'btn-secondary'}`}
                onClick={() => setSkt(d)}
              >
                {d} gün
              </button>
            ))}
          </div>
          <div className="field" style={{ marginTop: 8 }}>
            <input type="number" min="1" max="14" value={skt_days} onChange={(e) => setSkt(e.target.value)} />
          </div>
        </div>
        <div className="field">
          <label>Açıklama (opsiyonel)</label>
          <textarea rows="2" value={description} onChange={(e) => setDesc(e.target.value)} />
        </div>
        {user.role === 'super_admin' && (
          <div className="field">
            <label>Mağaza</label>
            <select value={store_id} onChange={(e) => setStoreId(e.target.value)}>
              <option value="">Genel — tüm mağazalar kullanabilir</option>
              {stores.map((s) => <option key={s.id} value={s.id}>Yalnızca: {s.name}</option>)}
            </select>
          </div>
        )}
        <div className="field">
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 500 }}>
            <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} style={{ width: 'auto' }} />
            Aktif
          </label>
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary">Kaydet</button>
        </div>
      </form>
    </Modal>
  );
}
