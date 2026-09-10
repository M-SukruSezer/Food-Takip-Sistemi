import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { User, Lock, Globe, Eye, EyeOff } from 'lucide-react';import { useAuth } from '../auth';
import { errorMessage } from '../format';
import { isNative, setApiBaseUrl } from '../api';
import { toast } from '../components/ui';

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const [username, setUsername] = useState(localStorage.getItem('rememberedUser') || '');
  const [password, setPassword] = useState('');
  const [show, setShow] = useState(false);
  const [remember, setRemember] = useState(!!localStorage.getItem('rememberedUser'));
  const [server, setServer] = useState(localStorage.getItem('apiUrl') || '');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const native = isNative();

  async function submit(e) {
    e.preventDefault();
    setError('');
    if (native && server.trim()) setApiBaseUrl(server);
    setBusy(true);
    try {
      await login(username, password);
      if (remember) localStorage.setItem('rememberedUser', username);
      else localStorage.removeItem('rememberedUser');
      navigate('/dashboard');
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  function forgot() {
    toast('Şifre sıfırlama için yöneticinle iletişime geç');
  }

  return (
    <div className="login-page">
      <div className="login-col">
        <div className="login-top">
          <div className="brand">
            <img className="brand-mark" src="/logo.png" alt="Food Takip Sistemi" />
            <span>
              <div className="brand-name">Food<b>Takip</b></div>
              <div className="brand-sub">DONUK • SKT • TAKİP</div>
            </span>
          </div>
          <span className="login-ver">v1.0</span>
        </div>

        <div className="login-main">
        <img className="login-logo" src="/logo.png" alt="Food Takip Sistemi" />
        <h1 className="login-title">Giriş Yap</h1>
        <p className="login-sub">Hesabına erişmek için bilgilerini gir.</p>

        {error && <div className="alert error">{error}</div>}

        <form onSubmit={submit}>
          <label className="login-label">Kullanıcı Adı <i>*</i></label>
          <div className="input-wrap">
            <span className="in-ico"><User size={17} /></span>
            <input
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="kullaniciadi"
              autoFocus
              autoComplete="username"
              required
            />
          </div>

          <label className="login-label">Şifre <i>*</i></label>
          <div className="input-wrap">
            <span className="in-ico"><Lock size={17} /></span>
            <input
              type={show ? 'text' : 'password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              autoComplete="current-password"
              required
            />
            <button type="button" className="eye-btn" onClick={() => setShow((s) => !s)} aria-label="Şifreyi göster">
              {show ? <EyeOff size={18} /> : <Eye size={18} />}
            </button>
          </div>

          {native && (
            <>
              <label className="login-label">Sunucu Adresi <i>*</i></label>
              <div className="input-wrap">
                <span className="in-ico"><Globe size={17} /></span>
                <input
                  value={server}
                  onChange={(e) => setServer(e.target.value)}
                  placeholder="örn: 192.168.1.10:4000"
                  inputMode="url"
                />
              </div>
              <p className="login-hint">Sistemin çalıştığı bilgisayarın IP adresi ve portu</p>
            </>
          )}

          <div className="login-row">
            <label className="remember">
              <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
              Beni hatırla
            </label>
            <button type="button" className="link-red" onClick={forgot}>Şifremi unuttum</button>
          </div>

          <button className="btn-login" type="submit" disabled={busy}>
            {busy ? 'Giriş yapılıyor...' : 'Giriş Yap'}
          </button>
        </form>

        </div>
        <div className="login-foot">Food Takip Sistemi</div>
      </div>
    </div>
  );
}
