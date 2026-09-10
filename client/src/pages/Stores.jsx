import { useCallback, useEffect, useState } from 'react';
import { Store } from 'lucide-react';
import api from '../api';
import { Modal, Confirm, toast } from '../components/ui';
import { errorMessage } from '../format';

export default function Stores() {
  const [stores, setStores] = useState([]);
  const [reload, setReload] = useState(0);
  const [showAdd, setShowAdd] = useState(false);
  const [edit, setEdit] = useState(null);
  const [del, setDel] = useState(null);

  const load = useCallback(() => {
    api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, []);

  useEffect(() => { load(); }, [load, reload]);

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><Store size={20} /> Mağazalar</h2>
        <button className="btn btn-primary" onClick={() => setShowAdd(true)}>+ Yeni Mağaza</button>
      </div>

      <div className="grid products">
        {stores.map((s) => (
          <div className="card" key={s.id} style={{ marginBottom: 0 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <strong style={{ fontSize: 16 }}>{s.name}</strong>
              {s.active ? <span className="badge sold">Aktif</span> : <span className="badge discarded">Pasif</span>}
            </div>
            <div className="muted" style={{ fontSize: 13, marginTop: 4 }}>{s.address || 'Adres yok'}</div>
            <div className="muted" style={{ fontSize: 13 }}>{s.phone || ''}</div>
            <div style={{ display: 'flex', gap: 12, marginTop: 10, fontSize: 13 }}>
              <span><strong>{s.user_count}</strong> kullanıcı</span>
              <span><strong>{s.active_batch_count}</strong> aktif ürün</span>
            </div>
            <div className="actions" style={{ marginTop: 12 }}>
              <button className="btn btn-sm btn-secondary" onClick={() => setEdit(s)}>Düzenle</button>
              <button className="btn btn-sm btn-outline-danger" onClick={() => setDel(s)}>Sil</button>
            </div>
          </div>
        ))}
      </div>

      {stores.length === 0 && <div className="card"><p className="empty">Henüz mağaza eklenmemiş.</p></div>}

      {showAdd && (
        <StoreModal onClose={() => setShowAdd(false)} onDone={() => { setShowAdd(false); setReload((n) => n + 1); }} />
      )}
      {edit && (
        <StoreModal store={edit} onClose={() => setEdit(null)} onDone={() => { setEdit(null); setReload((n) => n + 1); }} />
      )}
      {del && (
        <Confirm
          title="Mağazayı Sil"
          message={`${del.name} silinecek. Mağazada kullanıcı veya ürün kaydı varsa silinemez, pasife alabilirsiniz.`}
          confirmLabel="Sil"
          onCancel={() => setDel(null)}
          onConfirm={async () => {
            try {
              await api.delete(`/stores/${del.id}`);
              toast('Mağaza silindi');
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

function StoreModal({ store, onClose, onDone }) {
  const [name, setName] = useState(store?.name || '');
  const [address, setAddress] = useState(store?.address || '');
  const [phone, setPhone] = useState(store?.phone || '');
  const [active, setActive] = useState(store ? store.active === 1 : true);
  const [err, setErr] = useState('');

  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      if (store) {
        await api.put(`/stores/${store.id}`, { name, address, phone, active });
        toast('Mağaza güncellendi');
      } else {
        await api.post('/stores', { name, address, phone });
        toast('Mağaza oluşturuldu');
      }
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }

  return (
    <Modal title={store ? 'Mağazayı Düzenle' : 'Yeni Mağaza'} onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Mağaza Adı</label>
          <input value={name} onChange={(e) => setName(e.target.value)} required />
        </div>
        <div className="field">
          <label>Adres</label>
          <textarea rows="2" value={address} onChange={(e) => setAddress(e.target.value)} />
        </div>
        <div className="field">
          <label>Telefon</label>
          <input value={phone} onChange={(e) => setPhone(e.target.value)} />
        </div>
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
