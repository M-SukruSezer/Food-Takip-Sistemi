import { useCallback, useEffect, useRef, useState } from 'react';
import { Bell } from 'lucide-react';
import api from '../api';
import { fmtDateTime } from '../format';

// Ust cubuktaki bildirim zili.
//
// Yoklama araligi 90 sn: bildirim "an be an" olmasi gereken bir sey degil,
// daha sik vurmak sunucuya bosuna yuk olurdu. Mobil uygulamada ayni arayuz
// telefonun bildirim merkezine de dusuruyor.
const ARALIK_MS = 90_000;

export default function NotificationBell() {
  const [okunmamis, setOkunmamis] = useState(0);
  const [acik, setAcik] = useState(false);
  const [liste, setListe] = useState(null);
  const kutu = useRef(null);

  const yukle = useCallback(async (tam = false) => {
    try {
      const r = await api.get('/pdks/notifications', {
        params: { limit: tam ? 50 : 20 },
        silent: true,
      });
      setOkunmamis(r.data.unread || 0);
      if (tam) setListe(r.data.items || []);
    } catch {
      // Arka plan yoklamasi: hata gosterilmez, sonraki turda tekrar denenir.
    }
  }, []);

  useEffect(() => {
    yukle();
    const t = setInterval(() => yukle(), ARALIK_MS);
    return () => clearInterval(t);
  }, [yukle]);

  // Disari tiklayinca kapansin: acik kalan panel diger icerigi orter.
  useEffect(() => {
    if (!acik) return undefined;
    function disari(e) {
      if (kutu.current && !kutu.current.contains(e.target)) setAcik(false);
    }
    document.addEventListener('mousedown', disari);
    return () => document.removeEventListener('mousedown', disari);
  }, [acik]);

  async function ac() {
    const yeni = !acik;
    setAcik(yeni);
    if (yeni) await yukle(true);
  }

  async function tumunuOku() {
    await api.post('/pdks/notifications/read-all', {}, { noToast: true });
    await yukle(true);
  }

  return (
    <div className="bildirim-sarmal" ref={kutu}>
      <button
        type="button"
        className="topbar-logout bildirim-dugme"
        onClick={ac}
        aria-label={okunmamis > 0 ? `${okunmamis} okunmamış bildirim` : 'Bildirimler'}
        title="Bildirimler"
      >
        <Bell size={18} />
        {okunmamis > 0 && (
          <span className="bildirim-rozet">{okunmamis > 99 ? '99+' : okunmamis}</span>
        )}
      </button>

      {acik && (
        <div className="bildirim-panel" role="dialog" aria-label="Bildirimler">
          <div className="bildirim-baslik">
            <strong>Bildirimler</strong>
            {okunmamis > 0 && (
              <button type="button" className="btn btn-sm btn-secondary" onClick={tumunuOku}>
                Tümünü okundu işaretle
              </button>
            )}
          </div>
          {liste === null ? (
            <p className="muted bildirim-bos">Yükleniyor...</p>
          ) : liste.length === 0 ? (
            <p className="muted bildirim-bos">Henüz bildiriminiz yok.</p>
          ) : (
            <ul className="bildirim-liste">
              {liste.map((n) => (
                <li key={n.id} className={n.read ? '' : 'yeni'}>
                  <strong>{n.title}</strong>
                  <span>{n.body}</span>
                  <time>{fmtDateTime(n.created_at)}</time>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
