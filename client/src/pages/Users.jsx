import { useCallback, useEffect, useState } from 'react';
import { Users as UsersIcon } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, Confirm, toast } from '../components/ui';
import {
  ROLE_LABELS, errorMessage, fmtDate,
  ALL_PERMISSIONS, PERMISSION_LABELS, DEFAULT_PERMISSIONS, grantablePermissions,
} from '../format';

export default function Users() {
  const { user } = useAuth();
  const [users, setUsers] = useState([]);
  const [stores, setStores] = useState([]);
  const [reload, setReload] = useState(0);
  const [showAdd, setShowAdd] = useState(false);
  const [edit, setEdit] = useState(null);
  const [reset, setReset] = useState(null);
  const [del, setDel] = useState(null);

  const load = useCallback(() => {
    api.get('/users').then((r) => setUsers(r.data)).catch(() => {});
    if (user.role === 'super_admin') api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [user.role]);

  useEffect(() => { load(); }, [load, reload]);

  const isSuper = user.role === 'super_admin';

  async function toggleActive(target) {
    try {
      await api.put(`/users/${target.id}`, { active: !target.active }, {
        successMessage: target.active ? 'Kullanıcı pasife alındı' : 'Kullanıcı aktifleştirildi',
      });
      setReload((n) => n + 1);
    } catch {
      // Bildirim API katmaninda gosterilir.
    }
  }

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><UsersIcon size={20} /> Kullanıcılar</h2>
        <button className="btn btn-primary" onClick={() => setShowAdd(true)}>+ Kullanıcı Ekle</button>
      </div>

      <div className="card table-card" style={{ padding: 0, overflow: 'hidden' }}>
        <div className="table-wrap">
          <table className="responsive users-table">
            <thead>
              <tr><th>Kullanıcı</th><th>Ad Soyad</th><th>Rol</th><th>Mağaza</th><th>Yetkiler</th><th>Durum</th><th>Kayıt</th><th>İşlemler</th></tr>
            </thead>
            <tbody>
              {users.map((u) => (
                <tr key={u.id}>
                  <td data-label="Kullanıcı"><strong>{u.username}</strong></td>
                  <td data-label="Ad Soyad">{u.full_name}</td>
                  <td data-label="Rol">{ROLE_LABELS[u.role]}</td>
                  <td data-label="Mağaza">{u.store_name || (u.role === 'super_admin' ? '—' : '-')}</td>
                  <td data-label="Yetkiler" className="muted" style={{ fontSize: 12 }}>
                    {u.role === 'super_admin'
                      ? 'Tümü (rol gereği)'
                      : ((u.permissions && u.permissions.length > 0)
                          ? u.permissions.map((p) => PERMISSION_LABELS[p] || p).join(', ')
                          : 'Ek yetki yok')}
                  </td>
                  <td data-label="Durum">{u.active ? <span className="badge sold">Aktif</span> : <span className="badge discarded">Pasif</span>}</td>
                  <td data-label="Kayıt" className="muted" style={{ fontSize: 13 }}>{fmtDate(u.created_at)}</td>
                  <td data-label="İşlemler">
                    <div className="actions">
                      <button className="btn btn-sm btn-secondary" onClick={() => setEdit(u)}>Düzenle</button>
                      <button className="btn btn-sm btn-secondary" onClick={() => setReset(u)}>Şifre</button>
                      {u.id !== user.id && (
                        <>
                          <button
                            className={`btn btn-sm ${u.active ? 'btn-outline-danger' : 'btn-success'}`}
                            onClick={() => toggleActive(u)}
                          >
                            {u.active ? 'Pasife Al' : 'Aktifleştir'}
                          </button>
                          <button className="btn btn-sm btn-outline-danger" onClick={() => setDel(u)}>Sil</button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {showAdd && (
        <UserModal
          isSuper={isSuper}
          stores={stores}
          onClose={() => setShowAdd(false)}
          onDone={() => { setShowAdd(false); setReload((n) => n + 1); }}
        />
      )}
      {edit && (
        <UserModal
          isSuper={isSuper}
          user={edit}
          stores={stores}
          onClose={() => setEdit(null)}
          onDone={() => { setEdit(null); setReload((n) => n + 1); }}
        />
      )}
      {reset && (
        <ResetModal
          username={reset.username}
          onClose={() => setReset(null)}
          onDone={() => { setReset(null); setReload((n) => n + 1); }}
        />
      )}
      {del && (
        <Confirm
          title="Kullanıcıyı Sil"
          message={`${del.full_name} (${del.username}) kullanıcısı silinecek. Emin misiniz?`}
          confirmLabel="Sil"
          onCancel={() => setDel(null)}
          onConfirm={async () => {
            try {
              await api.delete(`/users/${del.id}`, { successMessage: 'Kullanıcı silindi' });
            } catch {
              // Bildirim API katmaninda gosterilir.
            }
            setDel(null);
            setReload((n) => n + 1);
          }}
        />
      )}
    </div>
  );
}

function UserModal({ isSuper, user, stores, onClose, onDone }) {
  const { user: me } = useAuth();
  const [username, setUsername] = useState(user?.username || '');
  const [full_name, setFullName] = useState(user?.full_name || '');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState(user?.role || 'staff');
  const [store_id, setStoreId] = useState(user?.store_id || '');
  const [active, setActive] = useState(user ? user.active === 1 : true);
  const [permissions, setPermissions] = useState(
    user ? (user.permissions || []) : DEFAULT_PERMISSIONS
  );
  const [err, setErr] = useState('');

  const editing = !!user;
  // Yalnizca kendi sahip oldugu yetkiyi devredebilir; sunucu da ayni kurali
  // uyguluyor, buradaki liste kutulari kilitlemek icin.
  const grantable = grantablePermissions(me);

  function togglePermission(permission, on) {
    setPermissions((list) => (on
      ? [...new Set([...list, permission])]
      : list.filter((p) => p !== permission)));
  }

  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      if (editing) {
        const payload = { full_name, role, active };
        if (isSuper && store_id !== '') payload.store_id = Number(store_id);
        // Ana Yonetici hesabinda yetkiler rolden gelir, gonderilmez.
        if (role !== 'super_admin') payload.permissions = permissions;
        await api.put(`/users/${user.id}`, payload, { noToast: true });
        toast('Kullanıcı güncellendi');
      } else {
        await api.post('/users', {
          username, password, full_name, role,
          store_id: store_id === '' ? undefined : Number(store_id),
          active,
          permissions: role === 'super_admin' ? undefined : permissions,
        }, { noToast: true });
        toast('Kullanıcı oluşturuldu');
      }
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }

  const roleOptions = isSuper
    ? ['store_manager', 'staff', 'super_admin']
    : ['store_manager', 'staff'];

  return (
    <Modal title={editing ? 'Kullanıcıyı Düzenle' : 'Yeni Kullanıcı'} onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        {!editing && (
          <div className="field">
            <label>Kullanıcı Adı</label>
            <input value={username} onChange={(e) => setUsername(e.target.value)} required />
          </div>
        )}
        {!editing && (
          <div className="field">
            <label>Şifre (en az 6 karakter)</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={6} />
          </div>
        )}
        <div className="field">
          <label>Ad Soyad</label>
          <input value={full_name} onChange={(e) => setFullName(e.target.value)} required />
        </div>
        <div className="field">
          <label>Rol</label>
          <select value={role} onChange={(e) => setRole(e.target.value)}>
            {roleOptions.map((r) => <option key={r} value={r}>{ROLE_LABELS[r]}</option>)}
          </select>
        </div>
        {isSuper && (
          <div className="field">
            <label>Mağaza</label>
            <select value={store_id} onChange={(e) => setStoreId(e.target.value)} disabled={role === 'super_admin'}>
              <option value="">— (Mağaza yok)</option>
              {stores.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
        )}
        {role !== 'super_admin' && (
          <div className="field">
            <label>Yetkiler</label>
            <div className="permission-list">
              {ALL_PERMISSIONS.map((permission) => {
                const allowed = grantable.includes(permission);
                return (
                  <label key={permission} className="permission-row">
                    <input
                      type="checkbox"
                      checked={permissions.includes(permission)}
                      disabled={!allowed}
                      onChange={(e) => togglePermission(permission, e.target.checked)}
                    />
                    {PERMISSION_LABELS[permission]}
                  </label>
                );
              })}
            </div>
            <p className="muted" style={{ fontSize: 12, margin: '6px 0 0' }}>
              {grantable.length < ALL_PERMISSIONS.length
                ? 'Yalnızca kendi sahip olduğunuz yetkileri verebilirsiniz.'
                : 'İşaretlenmeyen yetkiyle bu kullanıcı o işlemi yapamaz.'}
            </p>
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

function ResetModal({ username, onClose, onDone }) {
  const [password, setPassword] = useState('');
  const [err, setErr] = useState('');
  async function submit(e) {
    e.preventDefault();
    setErr('');
    try {
      const user = await api.get('/users').then((r) => r.data.find((u) => u.username === username));
      await api.post(`/users/${user.id}/password`, { password }, { noToast: true });
      toast('Şifre sıfırlandı');
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }
  return (
    <Modal title={`Şifre Sıfırla — ${username}`} onClose={onClose}>
      <form onSubmit={submit}>
        {err && <div className="alert error">{err}</div>}
        <div className="field">
          <label>Yeni Şifre (en az 6 karakter)</label>
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={6} />
        </div>
        <div className="form-actions">
          <button type="button" className="btn btn-secondary" onClick={onClose}>Vazgeç</button>
          <button type="submit" className="btn btn-primary">Kaydet</button>
        </div>
      </form>
    </Modal>
  );
}
