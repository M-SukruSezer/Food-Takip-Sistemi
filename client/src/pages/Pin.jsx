import { useCallback, useEffect, useRef, useState } from 'react';
import { Hash, RefreshCw } from 'lucide-react';
import api from '../api';
import { errorMessage } from '../format';

// PIN Dogrulama (magaza muduru ve vardiya sorumlusu): QR okutamayan partnerin
// girecegi 6 haneli kod. Kod sunucuda magaza sirrindan uretilir ve 60 sn'de
// bir degisir; sayac bitince ekran yeni kodu kendiliginden ceker.
export default function Pin() {
  const [pin, setPin] = useState(null);
  const [kalan, setKalan] = useState(0);
  const [hata, setHata] = useState('');
  const yukleniyor = useRef(false);

  const getir = useCallback(async () => {
    if (yukleniyor.current) return;
    yukleniyor.current = true;
    try {
      const r = await api.get('/pdks/pin/current', { noToast: true, silent: true });
      setPin(r.data);
      setKalan(r.data.expires_in);
      setHata('');
    } catch (e) {
      setHata(errorMessage(e));
      setKalan(0);
    } finally {
      yukleniyor.current = false;
    }
  }, []);

  useEffect(() => { getir(); }, [getir]);

  useEffect(() => {
    if (!pin) return undefined;
    const t = setInterval(() => {
      setKalan((k) => {
        if (k <= 1) { getir(); return 0; }
        return k - 1;
      });
    }, 1000);
    return () => clearInterval(t);
  }, [pin, getir]);

  const toplam = (pin && pin.window_seconds) || 60;
  const az = kalan <= 10;

  return (
    <div className="page-shell">
      <div className="page-head"><h2><Hash size={20} /> PIN Doğrulama</h2></div>
      <section className="surface-panel pin-panel">
        {pin && pin.store && <p className="muted" style={{ margin: 0 }}>{pin.store.name}</p>}
        {hata && <div className="alert error">{hata}</div>}
        {!hata && pin && (
          <>
            <div className="pin-kod" aria-live="polite">
              {pin.pin.slice(0, 3)} {pin.pin.slice(3)}
            </div>
            <div className="pin-sayac">
              <div className={`pin-sayac-dolgu ${az ? 'az' : ''}`} style={{ width: `${(kalan / toplam) * 100}%` }} />
            </div>
            <p className={az ? 'text-warning' : 'muted'} style={{ margin: 0, fontWeight: 600 }}>
              {kalan} sn sonra yenilenir
            </p>
          </>
        )}
        <p className="muted" style={{ fontSize: 'var(--fs-label)', margin: 0 }}>
          QR okutamayan partner, QR ekranında &quot;PIN ile Giriş&quot;i seçip bu kodu girer.
          Kod 60 saniye geçerlidir.
        </p>
        {hata && (
          <button type="button" className="btn btn-secondary" onClick={getir}>
            <RefreshCw size={16} /> Tekrar Dene
          </button>
        )}
      </section>
    </div>
  );
}
