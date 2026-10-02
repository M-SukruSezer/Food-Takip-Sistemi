import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Users as UsersIcon, Pencil, KeyRound, UserX, UserCheck, UserPlus, Trash2, Smartphone, SmartphoneNfc, Lock,
} from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { Modal, Confirm, toast } from '../components/ui';
import { Fab, SearchField, SwipeRow } from '../components/actions';
import {
  ROLE_LABELS, errorMessage, fmtDateTime, normalizeSearch, ALL_PERMISSIONS, PERMISSION_LABELS, DEFAULT_PERMISSIONS, grantablePermissions, rolesBelow, MULTI_STORE_ROLES,
} from '../format';

function initials(name) {
  return (name || '?').trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join('').toLocaleUpperCase('tr-TR');
}

export default function Users() {
  const { user } = useAuth();
  const [users, setUsers] = useState([]);
  const [stores, setStores] = useState([]);
  const [reload, setReload] = useState(0);
  const [showAdd, setShowAdd] = useState(false);
  const [edit, setEdit] = useState(null);
  const [reset, setReset] = useState(null);
  const [del, setDel] = useState(null);
  const [toggle, setToggle] = useState(null);
  const [search, setSearch] = useState('');

  const load = useCallback(() => {
    api.get('/users').then((r) => setUsers(r.data)).catch(() => {});
    if (user.role === 'super_admin') api.get('/stores').then((r) => setStores(r.data)).catch(() => {});
  }, [user.role]);

  useEffect(() => { load(); }, [load, reload]);

  const isSuper = user.role === 'super_admin';
  const shown = useMemo(() => {
    const q = normalizeSearch(search.trim());
    if (!q) return users;
    return users.filter((u) => normalizeSearch(u.full_name).includes(q) || normalizeSearch(u.username).includes(q));
  }, [users, search]);

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

  // Hesap-telefon eslestirmesi: bloke kaldirma (telefon ayni kalir) ve
  // cihaz sifirlama (bir sonraki giriste yeni telefona eslesir).
  const [cihaz, setCihaz] = useState(null); // { user, kind }

  async function deviceAction() {
    const { user: target, kind } = cihaz;
    try {
      await api.post(`/users/${target.id}/device/${kind}`, null, {
        successMessage: kind === 'unblock' ? 'Hesabın blokesi kaldırıldı' : 'Cihaz eşleşmesi sıfırlandı',
      });
    } catch {
      // Bildirim API katmaninda gosterilir.
    }
    setCihaz(null);
    setReload((n) => n + 1);
  }

  const cihazli = (u) => u.role !== 'super_admin' && u.role !== 'store';

  return (
    <div className="page-shell">
      <div className="page-head">
        <h2><UsersIcon size={20} /> Kullanıcılar</h2>
      </div>

      <div className="summary-row">
        <div className="summary-tile">
          <span>TOPLAM</span>
          <strong>{users.length} Kişi</strong>
          <em className="tone-success">Tam Kadro</em>
        </div>
        <div className="summary-tile">
          <span>GÖREVDE</span>
          <strong>{users.filter((u) => u.active).length} Kişi</strong>
          <em className="tone-info">{users.filter((u) => u.role === 'shift_supervisor').length} Şef</em>
        </div>
        <div className="summary-tile">
          <span>YETKİ</span>
          <strong>{users.filter((u) => (u.permissions || []).length > 0).length} Kişi</strong>
          <em className="tone-primary">Güncel</em>
        </div>
      </div>

      {/* Oneri Satis Listesi'ndeki arama kutusunun aynisi. */}
      <SearchField value={search} onChange={setSearch} placeholder="Personel veya kullanıcı adı ara..." />

      {shown.length === 0 ? (
        <div className="card">
          <p className="empty">{search.trim() ? 'Aramanıza uyan kullanıcı yok.' : 'Kullanıcı bulunamadı.'}</p>
        </div>
      ) : (
        <div className="swipe-list">
          {shown.map((u) => {
            const self = u.id === user.id;
            const cihazSifirla = cihazli(u) && u.device_bound;
            // Duzenle, Sifre, Pasife Al, Cihaz ve Sil kart soldan saga
            // kaydirilinca acilir.
            const actions = [
              { label: 'Düzenle', icon: Pencil, tone: 'primary', onClick: () => setEdit(u) },
              { label: 'Şifre', icon: KeyRound, tone: 'info', onClick: () => setReset(u) },
              ...(!self ? [{
                label: u.active ? 'Pasife Al' : 'Aktifleştir',
                icon: u.active ? UserX : UserCheck,
                tone: 'warning',
                onClick: () => setToggle(u),
              }] : []),
              ...(!self && cihazSifirla ? [{ label: 'Cihaz', icon: SmartphoneNfc, tone: 'ink', onClick: () => setCihaz({ user: u, kind: 'reset' }) }] : []),
              ...(!self ? [{ label: 'Sil', icon: Trash2, tone: 'danger', onClick: () => setDel(u) }] : []),
            ];
            return (
              <SwipeRow key={u.id} actions={actions} actionWidth={actions.length > 4 ? 64 : 72}>
                <article className="card user-card">
                  <div className="user-card-head">
                    <span className="user-initials">{initials(u.full_name)}</span>
                    <div className="user-card-name">
                      <strong>{u.full_name}</strong>
                      <span className="muted">@{u.username}</span>
                    </div>
                    {u.device_blocked
                      ? <span className="badge critical">bloke</span>
                      : (u.active ? <span className="badge sold">aktif</span> : <span className="badge critical">pasif</span>)}
                  </div>
                  <div className="chip-row" style={{ gap: 6, marginTop: 10 }}>
                    <span className="badge info">{ROLE_LABELS[u.role] || u.role}</span>
                    <span className="badge warning">
                      {MULTI_STORE_ROLES.includes(u.role)
                        ? `${(u.store_ids || []).length} mağaza sorumlusu`
                        : (u.store_name || (u.role === 'super_admin' ? 'Tüm mağazalar' : 'Mağaza atanmamış'))}
                    </span>
                  </div>
                  {u.role !== 'super_admin' && (
                    <p className="muted user-card-line">
                      {(u.permissions || []).length > 0
                        ? `Yetkiler: ${u.permissions.map((p) => PERMISSION_LABELS[p] || p).join(', ')}`
                        : 'Ek yetki verilmemiş'}
                    </p>
                  )}
                  {cihazli(u) && (
                    <p className="muted user-card-line">
                      {u.device_bound ? <Smartphone size={14} /> : <SmartphoneNfc size={14} />}
                      {u.device_bound ? ` Telefon: ${u.device_name || 'kayıtlı'}` : ' Telefon eşleşmedi'}
                    </p>
                  )}
                  {u.device_blocked && (
                    <div className="user-blocked">
                      <p>
                        <Lock size={16} /> Hesap bloke: başka bir telefondan
                        {u.blocked_device_name ? ` (${u.blocked_device_name})` : ''} açılmaya çalışıldı
                        {u.device_blocked_at ? ` · ${fmtDateTime(u.device_blocked_at)}` : ''}.
                      </p>
                      <div className="petty-presets two">
                        <button type="button" className="btn btn-sm btn-secondary" onClick={() => setCihaz({ user: u, kind: 'reset' })}>Cihazı Sıfırla</button>
                        <button type="button" className="btn btn-sm btn-primary" onClick={() => setCihaz({ user: u, kind: 'unblock' })}>Blokeyi Kaldır</button>
                      </div>
                    </div>
                  )}
                  {self && (
                    <p className="muted user-card-line">Kendi hesabınızı pasife alamaz veya silemezsiniz</p>
                  )}
                </article>
              </SwipeRow>
            );
          })}
        </div>
      )}

      <Fab icon={UserPlus} label="Yeni Kullanıcı" onClick={() => setShowAdd(true)} />

      {toggle && (
        <Confirm
          title={toggle.active ? 'Kullanıcıyı Pasife Al' : 'Kullanıcıyı Aktifleştir'}
          message={toggle.active
            ? `${toggle.full_name} artık sisteme giriş yapamayacak.`
            : `${toggle.full_name} yeniden giriş yapabilecek.`}
          confirmLabel={toggle.active ? 'Pasife Al' : 'Aktifleştir'}
          danger={!!toggle.active}
          onCancel={() => setToggle(null)}
          onConfirm={async () => { const t = toggle; setToggle(null); await toggleActive(t); }}
        />
      )}

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
      {cihaz && (
        <Confirm
          title={cihaz.kind === 'unblock' ? 'Blokeyi Kaldır' : 'Cihazı Sıfırla'}
          message={cihaz.kind === 'unblock'
            ? `${cihaz.user.full_name} hesabı yeniden açılacak. Kayıtlı telefonu aynı kalır; yeni telefona geçecekse "Cihazı Sıfırla"yı kullanın.`
            : `${cihaz.user.full_name} hesabının telefon eşleşmesi${cihaz.user.device_blocked ? ' ve blokesi' : ''} kaldırılacak. Bir sonraki girişte açtığı telefona eşleşir.`}
          confirmLabel={cihaz.kind === 'unblock' ? 'Kaldır' : 'Sıfırla'}
          onCancel={() => setCihaz(null)}
          danger={cihaz.kind !== 'unblock'}
          onConfirm={deviceAction}
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
  const [phone, setPhone] = useState(user?.phone || '');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState(user?.role || 'barista');
  const [store_id, setStoreId] = useState(user?.store_id || '');
  const [active, setActive] = useState(user ? user.active === 1 : true);
  const [permissions, setPermissions] = useState(
    user ? (user.permissions || []) : DEFAULT_PERMISSIONS
  );
  // Operations / Regional Manager birden fazla magazadan sorumlu olabilir.
  const [storeIds, setStoreIds] = useState(user ? (user.store_ids || []) : []);
  const multiStore = MULTI_STORE_ROLES.includes(role);
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
        const payload = { full_name, role, active, phone: phone.trim() || null };
        if (isSuper && store_id !== '') payload.store_id = Number(store_id);
        // Ana Yonetici hesabinda yetkiler rolden gelir, gonderilmez.
        if (role !== 'super_admin') payload.permissions = permissions;
        if (multiStore) payload.store_ids = storeIds;
        await api.put(`/users/${user.id}`, payload, { noToast: true });
        toast('Kullanıcı güncellendi');
      } else {
        await api.post('/users', {
          username, password, full_name, role, phone: phone.trim() || undefined,
          store_id: store_id === '' ? undefined : Number(store_id),
          active,
          permissions: role === 'super_admin' ? undefined : permissions,
          store_ids: multiStore ? storeIds : undefined,
        }, { noToast: true });
        toast('Kullanıcı oluşturuldu');
      }
      onDone();
    } catch (er) {
      setErr(errorMessage(er));
    }
  }

  // Yalnizca kendinden asagi kademedeki roller tanimlanabilir; sunucu da
  // ayni kurali uyguluyor.
  const roleOptions = rolesBelow(me && me.role);

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
          <label>Telefon</label>
          <input type="tel" placeholder="05xx xxx xx xx" value={phone} onChange={(e) => setPhone(e.target.value)} />
          <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '4px 0 0' }}>
            WhatsApp ile ekibe gönderim için kullanılır.
          </p>
        </div>
        <div className="field">
          <label>Rol</label>
          <select value={role} onChange={(e) => setRole(e.target.value)}>
            {roleOptions.map((r) => <option key={r} value={r}>{ROLE_LABELS[r]}</option>)}
          </select>
        </div>
        {multiStore ? (
          <div className="field">
            <label>Sorumlu Olduğu Mağazalar</label>
            <div className="permission-list">
              {stores.map((s) => (
                <label key={s.id} className="permission-row">
                  <input
                    type="checkbox"
                    checked={storeIds.includes(s.id)}
                    onChange={(e) => setStoreIds((list) => (e.target.checked
                      ? [...new Set([...list, s.id])]
                      : list.filter((id) => id !== s.id)))}
                  />
                  {s.name}
                </label>
              ))}
            </div>
            <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '6px 0 0' }}>
              Seçilen mağazaların verilerini görebilir.
            </p>
          </div>
        ) : (
          <div className="field">
            <label>Mağaza</label>
            <select value={store_id} onChange={(e) => setStoreId(e.target.value)}>
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
            <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: '6px 0 0' }}>
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
