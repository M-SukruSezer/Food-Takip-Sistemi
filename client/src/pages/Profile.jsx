import { useEffect, useRef, useState } from 'react';
import { User, Camera, Trash2, SunMedium, MoonStar } from 'lucide-react';
import api from '../api';
import { useAuth } from '../auth';
import { toast, Avatar } from '../components/ui';
import { ROLE_LABELS, errorMessage } from '../format';
import { getTheme, setTheme, subscribeTheme } from '../theme';

export default function Profile() {
  const { user, setUser } = useAuth();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const [avatarErr, setAvatarErr] = useState('');
  const fileRef = useRef(null);
  const [theme, setThemeState] = useState(getTheme);

  useEffect(() => subscribeTheme(setThemeState), []);

  async function submit(e) {
    e.preventDefault();
    setErr('');
    if (next !== confirm) {
      setErr('Yeni şifreler eşleşmiyor');
      return;
    }
    setBusy(true);
    try {
      await api.post('/auth/password', { current, next }, { noToast: true });
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

  // Gorseli tarayicida 256px'e kucultup JPEG'e cevirir: telefon fotolari
  // 3-5 MB geliyor, sunucu 300 KB ustunu reddediyor.
  function resize(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error('Dosya okunamadı'));
      reader.onload = () => {
        const img = new Image();
        img.onerror = () => reject(new Error('Görsel açılamadı'));
        img.onload = () => {
          const side = Math.min(img.width, img.height);
          const canvas = document.createElement('canvas');
          canvas.width = 256;
          canvas.height = 256;
          const ctx = canvas.getContext('2d');
          // Kareye ortalanarak kirpilir
          ctx.drawImage(img, (img.width - side) / 2, (img.height - side) / 2, side, side, 0, 0, 256, 256);
          resolve(canvas.toDataURL('image/jpeg', 0.82));
        };
        img.src = reader.result;
      };
      reader.readAsDataURL(file);
    });
  }

  async function pickAvatar(e) {
    const file = e.target.files && e.target.files[0];
    e.target.value = '';
    if (!file) return;
    setAvatarErr('');
    if (!/^image\//.test(file.type)) {
      setAvatarErr('Lütfen bir görsel dosyası seçin.');
      return;
    }
    try {
      const dataUrl = await resize(file);
      const r = await api.post('/auth/avatar', { avatar: dataUrl }, { successMessage: 'Profil fotoğrafı güncellendi' });
      setUser({ ...user, avatar: r.data.avatar });
    } catch (er) {
      setAvatarErr(errorMessage(er) === 'Bir hata oluştu' ? (er.message || 'Fotoğraf yüklenemedi') : errorMessage(er));
    }
  }

  async function removeAvatar() {
    setAvatarErr('');
    try {
      await api.post('/auth/avatar', { avatar: null }, { successMessage: 'Profil fotoğrafı kaldırıldı' });
      setUser({ ...user, avatar: null });
    } catch (er) {
      setAvatarErr(errorMessage(er));
    }
  }

  return (
    <div className="page-shell">
      <div className="page-head"><h2><User size={20} /> Profil</h2></div>

      <div className="card">
        <h3>Profil Fotoğrafı</h3>
        {avatarErr && <div className="alert error">{avatarErr}</div>}
        <div className="profile-photo">
          <Avatar user={user} size={84} />
          <div className="profile-photo-side">
            <div className="avatar-edit-actions">
              <button type="button" className="btn btn-secondary" onClick={() => fileRef.current && fileRef.current.click()}>
                <Camera size={16} /> {user.avatar ? 'Fotoğrafı Değiştir' : 'Fotoğraf Yükle'}
              </button>
              {user.avatar && (
                <button type="button" className="btn btn-outline-danger" onClick={removeAvatar}>
                  <Trash2 size={16} /> Kaldır
                </button>
              )}
            </div>
            <p className="avatar-hint">
              Seçtiğiniz fotoğraf otomatik olarak kare şekilde kırpılıp 256×256 boyutuna küçültülür.
            </p>
          </div>
        </div>
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          onChange={pickAvatar}
          style={{ display: 'none' }}
        />
      </div>

      <div className="surface-panel">
        <dl className="profile-info">
          <div><dt>Kullanıcı</dt><dd>{user.username}</dd></div>
          <div><dt>Ad Soyad</dt><dd>{user.full_name}</dd></div>
          <div><dt>Rol</dt><dd>{ROLE_LABELS[user.role]}</dd></div>
          <div><dt>Mağaza</dt><dd>{user.store_name || 'Merkezi'}</dd></div>
        </dl>
      </div>

      <div className="card">
        <h3>Görünüm</h3>
        <p className="avatar-hint" style={{ marginTop: 0 }}>
          Seçiminiz bu cihazda saklanır ve giriş ekranı dahil tüm ekranlarda geçerli olur.
        </p>
        <div className="theme-choice">
          <button
            type="button"
            className={`btn ${theme === 'light' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setTheme('light')}
            aria-pressed={theme === 'light'}
          >
            <SunMedium size={16} /> Açık Tema
          </button>
          <button
            type="button"
            className={`btn ${theme === 'dark' ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setTheme('dark')}
            aria-pressed={theme === 'dark'}
          >
            <MoonStar size={16} /> Koyu Tema
          </button>
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
