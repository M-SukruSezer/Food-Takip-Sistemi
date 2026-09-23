import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { User, Lock, Globe, Eye, EyeOff, AlertCircle } from 'lucide-react';
import { useAuth } from '../auth';
import { errorMessage } from '../format';
import { isNative, setApiBaseUrl, hasFixedApiUrl } from '../api';
import { toast } from '../components/ui';
import LoginArt from '../components/LoginArt';

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
  // Sunucu adresi yalnizca derlemede sabit bir API adresi yoksa sorulur.
  const askServer = isNative() && !hasFixedApiUrl();

  async function submit(e) {
    e.preventDefault();
    if (busy) return;
    setError('');
    if (askServer && server.trim()) setApiBaseUrl(server);
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
        {/* İllüstrasyon doğrudan zemin üzerinde; kart yok */}
        <LoginArt />

        {/* Altta marka renginde panel */}
        <div className="login-panel">
          <h1 className="login-title">Hoş geldin!</h1>

          {error && (
            <div className="login-error">
              <AlertCircle size={18} />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={submit}>
            <div className="pill-field">
              <span className="pill-ico"><User size={19} /></span>
              <input
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="Kullanıcı adı"
                aria-label="Kullanıcı adı"
                autoFocus
                autoComplete="username"
                required
              />
            </div>

            <div className="pill-field">
              <span className="pill-ico"><Lock size={19} /></span>
              <input
                type={show ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Şifre"
                aria-label="Şifre"
                autoComplete="current-password"
                required
              />
              <button type="button" className="pill-eye" onClick={() => setShow((s) => !s)} aria-label="Şifreyi göster">
                {show ? <EyeOff size={19} /> : <Eye size={19} />}
              </button>
            </div>

            {askServer && (
              <>
                <div className="pill-field">
                  <span className="pill-ico"><Globe size={19} /></span>
                  <input
                    value={server}
                    onChange={(e) => setServer(e.target.value)}
                    placeholder="Sunucu adresi — örn: 192.168.1.10:4000"
                    aria-label="Sunucu adresi"
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
              <button type="button" className="login-forgot" onClick={forgot}>Şifremi unuttum?</button>
            </div>

            <button className="btn-login" type="submit" disabled={busy}>
              {busy ? 'Giriş yapılıyor...' : 'Giriş Yap'}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}
