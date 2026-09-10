import { useState } from 'react';
import { User } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { toast } from '../components/ui';
import { ROLE_LABELS, errorMessage } from '../format';

export default function Profile() {
  const { user, setUser } = useAuth();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setErr('');
    if (next !== confirm) {
      setErr('Yeni şifreler eşleşmiyor');
      return;
    }
    setBusy(true);
    try {
      await api.post('/auth/password', { current, next });
      toast('Şifreniz güncellendi');
      setCurrent(''); setNext(''); setConfirm('');
      const me = await api.get('/auth/me');
      setUser(me.data);
    } catch (er) {
      setErr(errorMessage(er));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="page-shell">
      <div className="page-head"><h2><User size={20} /> Profil</h2></div>

      <div className="surface-panel">
        <div className="grid stats" style={{ gridTemplateColumns: 'repeat(2, 1fr)' }}>
          <div className="stat stat-card">
            <div className="label"><span>Kullanıcı</span></div>
            <div className="value" style={{ fontSize: 20 }}>{user.username}</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span>Ad Soyad</span></div>
            <div className="value" style={{ fontSize: 20 }}>{user.full_name}</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span>Rol</span></div>
            <div className="value" style={{ fontSize: 20 }}>{ROLE_LABELS[user.role]}</div>
          </div>
          <div className="stat stat-card">
            <div className="label"><span>Mağaza</span></div>
            <div className="value" style={{ fontSize: 20 }}>{user.store_name || 'Merkezi'}</div>
          </div>
        </div>
      </div>

      <div className="card">
        <h3>Şifre Değiştir</h3>
        <form onSubmit={submit} style={{ maxWidth: 380 }}>
          {err && <div className="alert error">{err}</div>}
          <div className="field">
            <label>Mevcut Şifre</label>
            <input type="password" value={current} onChange={(e) => setCurrent(e.target.value)} required />
          </div>
          <div className="field">
            <label>Yeni Şifre</label>
            <input type="password" value={next} onChange={(e) => setNext(e.target.value)} required minLength={6} />
          </div>
          <div className="field">
            <label>Yeni Şifre (Tekrar)</label>
            <input type="password" value={confirm} onChange={(e) => setConfirm(e.target.value)} required minLength={6} />
          </div>
          <button className="btn btn-primary" disabled={busy}>{busy ? 'Kaydediliyor...' : 'Şifreyi Güncelle'}</button>
        </form>
      </div>
    </div>
  );
}
